import Foundation
import ProviderAgentLoop
import ProviderConversation
import ProviderMessage
import ProviderMessageSender

/// 编辑并重发失败时抛出的错误。
public enum MessageEditError: Error, Equatable {
    /// 消息当前不可编辑。
    case notEligible(MessageEditEligibility)
    /// 提交的草稿不属于进行中的编辑会话。
    case noActiveEdit
    /// 回合在限定时间内没有停下；时间线未被改动。
    case cancelTimedOut
    /// 取消期间时间线被新的用户消息改写；时间线未被改动。
    case targetChanged
    /// 截断后提交被发送器排队，编辑后的消息没有落库。
    case commitQueued
    /// 截断后提交被发送器拒绝。
    case commitRejected
}

/// ``MessageEditingProviding`` 的实现。
///
/// 编辑 = 截断目标消息及其之后的全部消息，再把草稿作为同一会话里的新回合发出。
/// 只有会话里最新的一条真实用户消息可编辑。
@MainActor
public final class MessageEditor: MessageEditingProviding {
    /// 后台任务通知行的标记；这类 `.user` 行不是用户输入，不可编辑。
    public static let backgroundNotificationMetadataKey = "lumi.backgroundNotification"
    /// 等待运行中/挂起回合停下的最长时间。
    public static let cancelTimeoutNanoseconds: UInt64 = 5_000_000_000

    private let conversations: any ConversationManaging
    private let messages: any MessageManaging
    private let agentLoop: any AgentLoopProviding
    private let deleteToolCalls: ToolCallDeleter?
    private let messageSending: any MessageSendingProviding
    private var observers: [UUID: (MessageEditingEvent) -> Void] = [:]
    private var activeDraft: MessageEditDraft?
    private var isSubmitting = false
    /// 测试注入的取消等待上限。
    var cancelTimeoutNanoseconds = MessageEditor.cancelTimeoutNanoseconds

    /// 进行中的编辑草稿；没有编辑时为 nil。
    public var activeEdit: MessageEditDraft? { activeDraft }

    /// 清理被截断回合的工具调用记录（任务与调用历史）。
    public typealias ToolCallDeleter = @MainActor (_ turnIDs: [UUID], _ conversationID: UUID) async -> Void

    public init(
        conversations: any ConversationManaging,
        messages: any MessageManaging,
        agentLoop: any AgentLoopProviding,
        messageSending: any MessageSendingProviding,
        deleteToolCalls: ToolCallDeleter? = nil
    ) {
        self.conversations = conversations
        self.messages = messages
        self.agentLoop = agentLoop
        self.deleteToolCalls = deleteToolCalls
        self.messageSending = messageSending
    }

    // MARK: - MessageEditingProviding

    public func eligibility(for message: Message, in conversationID: UUID) -> MessageEditEligibility {
        guard message.conversationID == conversationID,
              let target = latestRealUserMessage(in: conversationID),
              target.id == message.id else {
            return .notLatestRealUserMessage
        }
        if agentLoop.isAutoReplySuppressed(for: conversationID) {
            return .autoReplySuppressed
        }
        if !messageSending.pendingMessages(for: conversationID).isEmpty {
            return .queuedMessagesPending
        }
        if messageSending.pendingAttachmentReadCount > 0 {
            return .attachmentsStillLoading
        }
        if activeDraft?.conversationID == conversationID {
            return .alreadyEditing
        }
        return Self.isEmptyDraft(Self.draft(for: target)) ? .emptyContent : .allowed
    }

    @discardableResult
    public func beginEditing(message: Message, in conversationID: UUID) -> Bool {
        guard eligibility(for: message, in: conversationID) == .allowed else { return false }
        let draft = Self.draft(for: message)
        activeDraft = draft
        notify(.began(draft))
        return true
    }

    public func cancelEditing(in conversationID: UUID) {
        guard let draft = activeDraft, draft.conversationID == conversationID else { return }
        activeDraft = nil
        notify(.ended(conversationID: conversationID))
    }

    public func submitEdit(_ draft: MessageEditDraft) async throws -> MessageSendCommit {
        guard !isSubmitting, let active = activeDraft else { throw MessageEditError.noActiveEdit }
        guard active.targetMessageID == draft.targetMessageID,
              active.conversationID == draft.conversationID else {
            throw MessageEditError.noActiveEdit
        }
        isSubmitting = true
        defer { isSubmitting = false }

        // 1. 提交前重新校验：目标必须仍是最新真实用户消息。
        _ = try removedMessages(for: draft)

        // 2. 运行中或挂起的回合先停下；超时则放弃，时间线保持原样。
        let state = agentLoop.state(for: draft.conversationID)
        if state == .running || state == .suspended {
            let settled = await settleTurn(in: draft.conversationID)
            guard settled else { throw MessageEditError.cancelTimedOut }
        }

        // 3. 等待期间可能有迟到的通知落进时间线，按当前时间线重新计算要删除的范围。
        let removed = try removedMessages(for: draft)

        // 4. 被移除回合的工具记录稍后清理。
        var turnIDs: [UUID] = []
        for turnID in removed.compactMap(\.turnID) where !turnIDs.contains(turnID) {
            turnIDs.append(turnID)
        }

        // 5. 截断。
        messages.deleteMessages(from: draft.targetMessageID, in: draft.conversationID)

        // 6. 作为新回合发出。此时若被排队，时间线已经截断而新消息没有落库：
        //    抛错并保留编辑会话，让用户可以重试。
        let commit = try messageSending.commitUserMessage(
            draft.content,
            imageAttachments: draft.imageAttachments,
            fileAttachments: draft.fileAttachments,
            collapsedBlocks: draft.collapsedBlocks,
            conversationID: draft.conversationID
        )
        guard let commit else { throw MessageEditError.commitRejected }
        guard commit.userMessageID != nil else { throw MessageEditError.commitQueued }

        // 7. 尽力清理被移除回合的工具记录。放在新消息落库之后：慢删除不能拖慢新回合，
        //    新回合使用新的 turnID，不会被误删。
        if let deleteToolCalls, !turnIDs.isEmpty {
            await deleteToolCalls(turnIDs, draft.conversationID)
        }

        // 8. 结束编辑会话。
        activeDraft = nil
        notify(.ended(conversationID: draft.conversationID))
        return commit
    }

    @discardableResult
    public func addObserver(_ callback: @escaping (MessageEditingEvent) -> Void) -> any MessageEditingObserverHandle {
        let id = UUID()
        observers[id] = callback
        return EditingObserverHandle { [weak self] in
            self?.observers.removeValue(forKey: id)
        }
    }

    // MARK: - Private

    private func notify(_ event: MessageEditingEvent) {
        for callback in observers.values {
            callback(event)
        }
    }

    /// 会话里最新的一条真实用户消息：排除时间线卡片和后台任务通知。
    func latestRealUserMessage(in conversationID: UUID) -> Message? {
        messages.messages(for: conversationID)
            .filter { message in
                message.role == .user
                    && !MessageTimelineEvent.isTimelineEvent(message)
                    && message.metadata[Self.backgroundNotificationMetadataKey] == nil
            }
            .max { lhs, rhs in
                if lhs.createdAt == rhs.createdAt { return lhs.id.uuidString < rhs.id.uuidString }
                return lhs.createdAt < rhs.createdAt
            }
    }

    /// 目标消息（含）之后的全部消息；目标已不在时间线里时抛错。
    private func removedMessages(for draft: MessageEditDraft) throws -> [Message] {
        // 与 `deleteMessages(from:in:)`、`messagePage` 同一套时间线顺序。
        let ordered = messages.messages(for: draft.conversationID).sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt { return lhs.id.uuidString < rhs.id.uuidString }
            return lhs.createdAt < rhs.createdAt
        }
        guard let index = ordered.firstIndex(where: { $0.id == draft.targetMessageID }) else {
            throw MessageEditError.targetChanged
        }
        let removed = Array(ordered[index...])
        guard !Self.isEmptyDraft(draft) else { throw MessageEditError.notEligible(.emptyContent) }
        // 等待取消期间若又有新的用户输入落库，目标就不再是最新的那条，不能再截断。
        let laterUserMessages = removed.dropFirst().filter { message in
            message.role == .user
                && !MessageTimelineEvent.isTimelineEvent(message)
                && message.metadata[Self.backgroundNotificationMetadataKey] == nil
        }
        guard laterUserMessages.isEmpty else { throw MessageEditError.targetChanged }
        return removed
    }

    private static func isEmptyDraft(_ draft: MessageEditDraft) -> Bool {
        draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.imageAttachments.isEmpty
            && draft.fileAttachments.isEmpty
    }

    /// 从已落库的用户消息还原编辑草稿；附件或折叠块损坏时退化为纯文本。
    static func draft(for message: Message) -> MessageEditDraft {
        MessageEditDraft(
            targetMessageID: message.id,
            conversationID: message.conversationID,
            content: message.content,
            imageAttachments: UserAttachmentMetadata.decodeImageAttachments(from: message.metadata),
            fileAttachments: UserAttachmentMetadata.decodeFileAttachments(from: message.metadata),
            collapsedBlocks: CollapsedContentBlockMetadata.normalizedBlocks(
                from: message.metadata,
                contentLength: message.content.count
            )
        )
    }

    /// 等回合停下，超过上限返回 `false`。
    private func settleTurn(in conversationID: UUID) async -> Bool {
        let timeoutNanoseconds = cancelTimeoutNanoseconds
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let waiter = SettleWaiter(continuation)
            Task { @MainActor [agentLoop] in
                await agentLoop.cancelTurnAndWait(in: conversationID)
                waiter.resume(true)
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                waiter.resume(false)
            }
        }
    }
}

@MainActor
private final class EditingObserverHandle: MessageEditingObserverHandle {
    private var cancellation: (() -> Void)?

    init(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        cancellation?()
        cancellation = nil
    }
}

/// 只允许恢复一次的等待者：回合停下与超时两条路径竞争同一个 continuation。
private final class SettleWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var continuation: CheckedContinuation<Bool, Never>?
    private var resumed = false

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Bool) {
        lock.lock()
        let pending = resumed ? nil : continuation
        resumed = true
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
