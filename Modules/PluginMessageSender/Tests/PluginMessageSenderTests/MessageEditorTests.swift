import Foundation
import KernelCore
import ProviderAgentLoop
import ProviderConversation
import ProviderLifecycleHooks
import ProviderMessage
import ProviderMessageSender
import Testing
@testable import PluginMessageSender

// MARK: - Test doubles

/// 按调用顺序记录事件的共享日志，用来断言「取消 → 截断 → 落库」的先后。
@MainActor
final class EditEventLog {
    private(set) var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }
}

/// 编辑测试用 AgentLoop 桩：回合状态由测试显式设置，取消等待的收尾时机也由测试控制。
@MainActor
final class EditingStubAgentLoop: AgentLoopProviding {
    var states: [UUID: AgentLoopState] = [:]
    var suppressed: Set<UUID> = []
    var suspensions: [UUID: AgentLoopSuspension] = [:]
    private(set) var cancelledConversationIDs: [UUID] = []
    /// `cancelTurnAndWait` 里执行的收尾：真实 AgentLoop 在这里投递终态事件并把回合置空。
    var onCancelAndWait: ((UUID) async -> Void)?
    weak var log: EditEventLog?
    private(set) var runTurnCount = 0

    func addAgentLoopObserver(
        _ callback: @escaping (AgentLoopEvent) -> Void
    ) -> any AgentLoopObserverHandle {
        EditingNoopAgentLoopObserverHandle()
    }

    func runTurn(in conversationID: UUID) async throws -> AgentLoopOutcome {
        runTurnCount += 1
        return .completed
    }

    func resumeTurn(in conversationID: UUID, request: AgentTurnResumeRequest) async throws -> AgentLoopOutcome {
        .completed
    }

    func cancelTurn(in conversationID: UUID) {
        cancelledConversationIDs.append(conversationID)
    }

    func cancelTurnAndWait(in conversationID: UUID) async {
        log?.append("cancel.begin")
        // 与真实 AgentLoop 一致：等待版取消同样会走一次同步取消。
        cancelTurn(in: conversationID)
        await onCancelAndWait?(conversationID)
        log?.append("cancel.end")
    }

    func state(for conversationID: UUID) -> AgentLoopState { states[conversationID] ?? .idle }
    func suspension(for conversationID: UUID) -> AgentLoopSuspension? { suspensions[conversationID] }
    func isRunning(for conversationID: UUID) -> Bool { state(for: conversationID) == .running }
    func currentTurnID(for conversationID: UUID) -> UUID? { nil }
    func isAutoReplySuppressed(for conversationID: UUID) -> Bool { suppressed.contains(conversationID) }
    func setAutoReplySuppressed(_ suppressed: Bool, for conversationID: UUID) {
        if suppressed { self.suppressed.insert(conversationID) } else { self.suppressed.remove(conversationID) }
    }
    func retryTurn(in conversationID: UUID, after failedTurnID: UUID) async throws -> AgentLoopOutcome { .cancelled }
    func setLifecycleHooks(_ hooks: (any LifecycleHooksProviding)?) {}
}

@MainActor
private final class EditingNoopAgentLoopObserverHandle: AgentLoopObserverHandle {
    func cancel() {}
}

/// 记录编辑器发起的工具记录清理。
@MainActor
final class ToolDeleterSpy {
    struct Call: Equatable {
        let turnIDs: [UUID]
        let conversationID: UUID
    }

    private(set) var calls: [Call] = []
    weak var log: EditEventLog?

    func record(_ turnIDs: [UUID], _ conversationID: UUID) {
        calls.append(Call(turnIDs: turnIDs, conversationID: conversationID))
        log?.append("deleteToolCalls")
    }
}

/// 编辑测试夹具：真实的内存消息管理器 + 真实 `MessageSender`，只替换 AgentLoop。
@MainActor
final class EditFixture {
    let conversations = DefaultConversationManager()
    let messages = DefaultMessageManager()
    let agentLoop = EditingStubAgentLoop()
    let sender: MessageSender
    let editor: MessageEditor
    let log = EditEventLog()
    let toolDeleter = ToolDeleterSpy()
    let conversationID: UUID
    private var observers: [any AnyObject] = []
    private var clock = 1_000.0

    init() throws {
        sender = MessageSender(conversations: conversations, messages: messages, agentLoop: agentLoop)
        conversationID = try conversations.createConversation(
            title: nil, projectPath: nil, providerID: nil, modelName: nil
        )
        let spy = toolDeleter
        editor = MessageEditor(
            conversations: conversations,
            messages: messages,
            agentLoop: agentLoop,
            messageSending: sender,
            deleteToolCalls: { turnIDs, conversationID in
                spy.record(turnIDs, conversationID)
            }
        )
        agentLoop.log = log
        spy.log = log
        let eventLog = log
        observers.append(messages.addMessageInsertedObserver { _, _ in
            eventLog.append("insert")
        })
        observers.append(messages.addMessageChangeObserver { change in
            if case .truncated = change { eventLog.append("truncate") }
        })
    }

    /// 按稳定的时间线顺序插入一条消息。
    @discardableResult
    func insert(
        _ role: MessageRole,
        content: String,
        turnID: UUID? = nil,
        metadata: [String: String] = [:],
        in conversationID: UUID? = nil
    ) -> Message {
        clock += 1
        let message = Message(
            conversationID: conversationID ?? self.conversationID,
            role: role,
            content: content,
            createdAt: Date(timeIntervalSince1970: clock),
            turnID: turnID,
            metadata: metadata
        )
        messages.insertMessage(message, to: message.conversationID)
        return message
    }

    func seedTwoTurns() throws -> (olderUser: Message, olderTurn: UUID, target: Message, targetTurn: UUID) {
        let olderTurn = UUID()
        let targetTurn = UUID()
        let olderUser = insert(.user, content: "first question", turnID: olderTurn)
        insert(.assistant, content: "first answer", turnID: olderTurn)
        let target = insert(.user, content: "second question", turnID: targetTurn)
        insert(.assistant, content: "partial answer", turnID: targetTurn)
        return (olderUser, olderTurn, target, targetTurn)
    }

    func contents() -> [String] {
        messages.messages(for: conversationID).sorted { $0.createdAt < $1.createdAt }.map(\.content)
    }
}

// MARK: - Tests

@Suite("MessageEditor 提交编辑")
@MainActor
struct MessageEditorTests {

    @Test("运行中的回合：先等待取消收尾，再截断，再落库新消息")
    func runningTurnIsSettledBeforeTruncation() async throws {
        let fixture = try EditFixture()
        let seeded = try fixture.seedTwoTurns()
        fixture.agentLoop.states[fixture.conversationID] = .running
        fixture.agentLoop.onCancelAndWait = { [weak fixture] conversationID in
            // 真实 AgentLoop 取消收尾时仍会写入一条迟到的消息；必须落在截断之前。
            fixture?.insert(.assistant, content: "late chunk", turnID: seeded.targetTurn)
            fixture?.agentLoop.states[conversationID] = .cancelled
        }

        let target = seeded.target
        let editor = fixture.editor
        #expect(editor.beginEditing(message: target, in: fixture.conversationID))
        let draft = MessageEditDraft(
            targetMessageID: target.id,
            conversationID: fixture.conversationID,
            content: "edited question"
        )
        let commit = try await editor.submitEdit(draft)

        #expect(commit.userMessageID != nil)
        let events = fixture.log.events
        let cancelEnd = try #require(events.firstIndex(of: "cancel.end"))
        let truncate = try #require(events.firstIndex(of: "truncate"))
        // 迟到消息先落库，随后才截断；编辑后的消息最后落库。
        #expect(events.firstIndex(of: "insert").map { $0 < cancelEnd } ?? false)
        #expect(events.lastIndex(of: "insert").map { $0 > truncate } ?? false)
        #expect(fixture.contents() == ["first question", "first answer", "edited question"])
        // 迟到的消息已随旧回合一起截断。
        #expect(!fixture.contents().contains("late chunk"))
        #expect(editor.activeEdit == nil)
        #expect(fixture.agentLoop.cancelledConversationIDs == [fixture.conversationID])
    }

    @Test("挂起的回合同样被取消并由编辑后的消息替换")
    func suspendedTurnIsCancelledAndReplaced() async throws {
        let fixture = try EditFixture()
        let seeded = try fixture.seedTwoTurns()
        let id = fixture.conversationID
        fixture.agentLoop.states[id] = .suspended
        fixture.agentLoop.suspensions[id] = AgentLoopSuspension(
            suspensionID: "auth:1", conversationID: id, toolCallID: "call-1",
            kind: "toolAuthorization", payload: "{}"
        )
        fixture.agentLoop.onCancelAndWait = { [weak fixture] conversationID in
            fixture?.agentLoop.states[conversationID] = .cancelled
        }

        let editor = fixture.editor
        #expect(editor.beginEditing(message: seeded.target, in: id))
        let commit = try await editor.submitEdit(MessageEditDraft(
            targetMessageID: seeded.target.id, conversationID: id, content: "edited question"
        ))

        #expect(commit.wasQueued == false)
        #expect(fixture.contents() == ["first question", "first answer", "edited question"])
    }

    @Test("取消超时：抛错且时间线保持原样，编辑会话保留")
    func cancelTimeoutLeavesTimelineUntouched() async throws {
        let fixture = try EditFixture()
        let seeded = try fixture.seedTwoTurns()
        fixture.agentLoop.states[fixture.conversationID] = .running
        // 收尾永不返回：模拟卡住的回合。
        var release: CheckedContinuation<Void, Never>?
        fixture.agentLoop.onCancelAndWait = { _ in
            await withCheckedContinuation { release = $0 }
        }
        fixture.editor.cancelTimeoutNanoseconds = 50_000_000

        let editor = fixture.editor
        #expect(editor.beginEditing(message: seeded.target, in: fixture.conversationID))
        await #expect(throws: MessageEditError.cancelTimedOut) {
            try await editor.submitEdit(MessageEditDraft(
                targetMessageID: seeded.target.id,
                conversationID: fixture.conversationID,
                content: "edited question"
            ))
        }

        #expect(fixture.contents() == ["first question", "first answer", "second question", "partial answer"])
        #expect(fixture.log.events.contains("truncate") == false)
        #expect(editor.activeEdit != nil)
        #expect(fixture.agentLoop.cancelledConversationIDs == [fixture.conversationID])

        release?.resume()
    }

    @Test("工具记录清理只收到被截断回合的 turnID")
    func toolDeletionReceivesOnlyRemovedTurns() async throws {
        let fixture = try EditFixture()
        let seeded = try fixture.seedTwoTurns()
        let editor = fixture.editor
        #expect(editor.beginEditing(message: seeded.target, in: fixture.conversationID))
        let commit = try await editor.submitEdit(MessageEditDraft(
            targetMessageID: seeded.target.id, conversationID: fixture.conversationID, content: "edited"
        ))

        #expect(commit.userMessageID != nil)
        #expect(fixture.toolDeleter.calls.map(\.turnIDs) == [[seeded.targetTurn]])
        #expect(fixture.toolDeleter.calls.map(\.conversationID) == [fixture.conversationID])
        // 清理发生在新消息落库之后。
        let insertIndex = try #require(fixture.log.events.firstIndex(of: "insert"))
        let deleteIndex = try #require(fixture.log.events.firstIndex(of: "deleteToolCalls"))
        #expect(deleteIndex > insertIndex)
    }

    @Test("提交被排队时抛错并保留草稿")
    func queuedCommitThrowsAndKeepsDraft() async throws {
        let fixture = try EditFixture()
        let seeded = try fixture.seedTwoTurns()
        let id = fixture.conversationID
        fixture.agentLoop.states[id] = .running
        // 取消没有让会话空闲下来：提交会被发送器排队。
        fixture.agentLoop.onCancelAndWait = { _ in }

        let editor = fixture.editor
        let draft = MessageEditDraft(
            targetMessageID: seeded.target.id, conversationID: id, content: "edited question"
        )
        #expect(editor.beginEditing(message: seeded.target, in: id))
        await #expect(throws: MessageEditError.commitQueued) {
            try await editor.submitEdit(draft)
        }

        #expect(fixture.sender.pendingMessages(for: id).map(\.content) == ["edited question"])
        #expect(editor.activeEdit?.targetMessageID == draft.targetMessageID)
        // 编辑后的消息只是排队，没有落库。
        #expect(fixture.messages.messages(for: id).contains { $0.content == "edited question" } == false)
    }

    @Test("附件与折叠块在预填与提交后都保留")
    func attachmentsAndCollapsedBlocksSurvivePrefillAndSubmit() async throws {
        let fixture = try EditFixture()
        let image = UserImageAttachment.fixture()
        let file = UserFileAttachment.fixture()
        let block = CollapsedContentBlock(start: 0, length: 4, title: "pasted.txt")
        var metadata = UserAttachmentMetadata.encodeImageAttachments([image])
        metadata.merge(UserAttachmentMetadata.encodeFileAttachments([file])) { _, new in new }
        metadata.merge(CollapsedContentBlockMetadata.encodeCollapsedBlocks([block])) { _, new in new }
        let content = "0123 rest"
        let target = fixture.insert(.user, content: content, turnID: UUID(), metadata: metadata)

        let editor = fixture.editor
        #expect(editor.beginEditing(message: target, in: fixture.conversationID))
        let prefilled = try #require(editor.activeEdit)
        #expect(prefilled.imageAttachments == [image])
        #expect(prefilled.fileAttachments == [file])
        #expect(prefilled.collapsedBlocks == [block])

        let submitted = MessageEditDraft(
            targetMessageID: target.id,
            conversationID: fixture.conversationID,
            content: content,
            imageAttachments: prefilled.imageAttachments,
            fileAttachments: prefilled.fileAttachments,
            collapsedBlocks: prefilled.collapsedBlocks
        )
        let commit = try await editor.submitEdit(submitted)

        let stored = try #require(commit.userMessageID.flatMap { fixture.messages.message(id: $0, in: fixture.conversationID) })
        #expect(UserAttachmentMetadata.decodeImageAttachments(from: stored.metadata) == [image])
        #expect(UserAttachmentMetadata.decodeFileAttachments(from: stored.metadata) == [file])
        #expect(CollapsedContentBlockMetadata.normalizedBlocks(
            from: stored.metadata, contentLength: stored.content.count
        ) == [block])
    }
}
