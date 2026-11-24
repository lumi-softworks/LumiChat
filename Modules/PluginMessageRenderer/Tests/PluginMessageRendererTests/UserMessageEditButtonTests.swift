import Foundation
import KernelCore
import KitAgentTool
import ProviderAgentLoop
import ProviderConversation
import ProviderDeveloperMode
import ProviderMessage
import ProviderMessageRendering
import ProviderMessageSender
import ProviderToolManager
import Testing
@testable import PluginMessageRenderer

// 既有测试替身不关心编辑入口：默认一律不提供。
extension MessageRendererCapability {
    func canEditUserMessage(_ message: Message, conversationID: UUID) -> Bool { false }

    func beginEditingUserMessage(_ message: Message, conversationID: UUID) {}
}

/// 记录裁决与开始编辑请求的编辑 Provider 替身。
@MainActor
private final class StubEditingProvider: MessageEditingProviding {
    /// 每条消息的裁决；未登记的消息按「不是最新一条真实用户消息」处理。
    var eligibilities: [UUID: MessageEditEligibility] = [:]
    private(set) var eligibilityChecks: [(messageID: UUID, conversationID: UUID)] = []
    private(set) var began: [(messageID: UUID, conversationID: UUID)] = []

    func eligibility(for message: Message, in conversationID: UUID) -> MessageEditEligibility {
        eligibilityChecks.append((message.id, conversationID))
        return eligibilities[message.id] ?? .notLatestRealUserMessage
    }

    func beginEditing(message: Message, in conversationID: UUID) -> Bool {
        began.append((message.id, conversationID))
        return true
    }

    func cancelEditing(in conversationID: UUID) {}

    func submitEdit(_ draft: MessageEditDraft) async throws -> MessageSendCommit {
        struct NotSubmitted: Error {}
        throw NotSubmitted()
    }
}

/// 把编辑相关调用转给 `StubEditingProvider` 的渲染能力替身。
@MainActor
private final class EditStubRendererCapability: MessageRendererCapability {
    let editing: StubEditingProvider?

    init(editing: StubEditingProvider?) {
        self.editing = editing
    }

    func toolCallResult(
        for toolCallID: String,
        conversationID: UUID,
        turnID: UUID?
    ) async -> ToolCallResult? {
        nil
    }

    func resendMessage(_ message: Message) async {}

    func canEditUserMessage(_ message: Message, conversationID: UUID) -> Bool {
        editing?.eligibility(for: message, in: conversationID) == .allowed
    }

    func beginEditingUserMessage(_ message: Message, conversationID: UUID) {
        editing?.beginEditing(message: message, in: conversationID)
    }

    func canRetryTurn(turnID: UUID, conversationID: UUID) -> Bool { false }

    func retryTurn(turnID: UUID, conversationID: UUID) async {}

    func canStopTurn(conversationID: UUID) -> Bool { false }

    func stopTurn(conversationID: UUID) {}

    func toolCallRenderer(for toolCall: ToolCall) -> (any ToolCallRowRenderer)? { nil }

    func makeToolJobActivityModel(
        toolCallID: String,
        conversationID: UUID,
        turnID: UUID?
    ) -> ToolJobActivityModel {
        ToolJobActivityModel(
            manager: nil,
            toolCallID: toolCallID,
            conversationID: conversationID,
            turnID: turnID
        )
    }

    var isDeveloperModeEnabled: Bool { false }

    func addDeveloperModeObserver(
        _ callback: @escaping (DeveloperModeProvidingEvent) -> Void
    ) -> any DeveloperModeProvidingObserverHandle {
        NoopDeveloperModeProvidingObserverHandle()
    }
}

private func userMessage(
    conversationID: UUID,
    content: String = "latest user message",
    metadata: [String: String] = [:]
) -> Message {
    Message(
        conversationID: conversationID,
        role: .user,
        content: content,
        metadata: metadata
    )
}

@Suite("用户消息编辑入口")
@MainActor
struct UserMessageEditButtonTests {
    private let conversationID = UUID()

    // MARK: - 可提供性

    @Test("只有裁决为 allowed 的最新一条用户消息才提供编辑入口")
    func offeredOnlyForEligibleLatestUserMessage() {
        let editing = StubEditingProvider()
        let capability = EditStubRendererCapability(editing: editing)
        let latest = userMessage(conversationID: conversationID)
        editing.eligibilities[latest.id] = .allowed

        #expect(UserMessageEditAction.isOffered(latest, capability: capability))
        #expect(editing.eligibilityChecks.count == 1)
        #expect(editing.eligibilityChecks.first?.messageID == latest.id)
        #expect(editing.eligibilityChecks.first?.conversationID == conversationID)
    }

    @Test("非最新一条、后台通知行与自动回复被抑制的会话都不提供编辑入口")
    func notOfferedForIneligibleRows() {
        let editing = StubEditingProvider()
        let capability = EditStubRendererCapability(editing: editing)
        let conversationID = UUID()
        let older = userMessage(conversationID: conversationID, content: "older question")
        let notification = userMessage(
            conversationID: conversationID,
            content: "Background task finished",
            metadata: ["lumi.backgroundNotification": "task-1"]
        )
        editing.eligibilities[notification.id] = .notLatestRealUserMessage
        let suppressed = userMessage(conversationID: conversationID)
        editing.eligibilities[suppressed.id] = .autoReplySuppressed
        let streaming = userMessage(conversationID: conversationID)
        editing.eligibilities[streaming.id] = .queuedMessagesPending

        #expect(!UserMessageEditAction.isOffered(older, capability: capability))
        #expect(!UserMessageEditAction.isOffered(notification, capability: capability))
        #expect(!UserMessageEditAction.isOffered(suppressed, capability: capability))
        #expect(!UserMessageEditAction.isOffered(streaming, capability: capability))
    }

    @Test("合成行与助手消息不询问编辑 Provider")
    func syntheticRowsAndOtherRolesSkipTheProvider() {
        let editing = StubEditingProvider()
        let capability = EditStubRendererCapability(editing: editing)
        let timelineEvent = Message(
            conversationID: conversationID,
            role: .user,
            content: "compaction",
            metadata: [
                MessageTimelineEvent.metadataKey: MessageTimelineEvent.contextCompaction,
            ]
        )
        let assistant = Message(conversationID: conversationID, role: .assistant, content: "answer")

        #expect(MessageTimelineEvent.isTimelineEvent(timelineEvent))
        #expect(!UserMessageEditAction.isOffered(assistant, capability: capability))
        #expect(!UserMessageEditAction.isOffered(timelineEvent, capability: capability))
        #expect(editing.eligibilityChecks.isEmpty)
    }

    @Test("行级状态随裁决刷新；没有 capability 时不提供")
    func offerStateFollowsEligibility() {
        let editing = StubEditingProvider()
        let capability = EditStubRendererCapability(editing: editing)
        let message = userMessage(conversationID: conversationID)
        let state = UserMessageEditOfferState()

        state.refresh(message, capability: capability)
        #expect(!state.isOffered)

        editing.eligibilities[message.id] = .allowed
        state.refresh(message, capability: capability)
        #expect(state.isOffered)

        editing.eligibilities[message.id] = .alreadyEditing
        state.refresh(message, capability: capability)
        #expect(!state.isOffered)

        state.refresh(message, capability: nil)
        #expect(!state.isOffered)
    }

    // MARK: - 点击

    @Test("点击编辑带着这条消息与它所属的会话调用 beginEditingUserMessage")
    func beginCarriesMessageAndConversation() {
        let editing = StubEditingProvider()
        let capability = EditStubRendererCapability(editing: editing)
        let message = userMessage(conversationID: conversationID)

        UserMessageEditAction.begin(message, capability: capability)

        #expect(editing.began.count == 1)
        #expect(editing.began.first?.messageID == message.id)
        #expect(editing.began.first?.conversationID == conversationID)
    }

    // MARK: - 能力层接线

    @Test("能力适配器把裁决与开始编辑转给 MessageEditingProviding")
    func adapterForwardsToEditingProvider() throws {
        let editing = StubEditingProvider()
        let kernel = KernelCoreContainer()
        try kernel.registerProvider((any MessageEditingProviding).self, editing)
        let capability = MessageRendererCapabilityAdapter(kernel: kernel)
        let allowed = userMessage(conversationID: conversationID)
        editing.eligibilities[allowed.id] = .allowed
        let suppressed = userMessage(conversationID: conversationID)
        editing.eligibilities[suppressed.id] = .autoReplySuppressed

        #expect(capability.canEditUserMessage(allowed, conversationID: conversationID))
        #expect(!capability.canEditUserMessage(suppressed, conversationID: conversationID))

        capability.beginEditingUserMessage(allowed, conversationID: conversationID)
        #expect(editing.began.count == 1)
        #expect(editing.began.first?.messageID == allowed.id)
        #expect(editing.began.first?.conversationID == conversationID)
    }

    @Test("没有装配编辑 Provider 时不提供编辑入口，点击是空操作")
    func adapterWithoutEditingProviderIsInert() throws {
        let capability = MessageRendererCapabilityAdapter(kernel: KernelCoreContainer())
        let message = userMessage(conversationID: conversationID)

        #expect(!capability.canEditUserMessage(message, conversationID: conversationID))
        capability.beginEditingUserMessage(message, conversationID: conversationID)
    }

    // MARK: - 无障碍

    @Test("编辑按钮使用固定 AX 标识符与「Edit」标签")
    func accessibilityIdentifierAndLabel() {
        #expect(UserMessageEditAccessibility.identifier == "lumi.user-message.edit")
        #expect(UserMessageEditAccessibility.label == pluginLocalization.string("Edit"))
        #expect(!UserMessageEditAccessibility.label.isEmpty)
    }

    @Test("未悬停时编辑按钮只是透明，不会从 AX 树里移除")
    func hiddenStateOnlyChangesOpacity() {
        // 可编辑性与悬停无关：行挂载时就定下来，悬停只负责让它看得见。
        let editing = StubEditingProvider()
        let capability = EditStubRendererCapability(editing: editing)
        let message = userMessage(conversationID: conversationID)
        editing.eligibilities[message.id] = .allowed
        let state = UserMessageEditOfferState()
        state.refresh(message, capability: capability)

        #expect(state.isOffered)
        #expect(UserMessageEditAccessibility.opacity(isVisible: false) == 0)
        #expect(UserMessageEditAccessibility.opacity(isVisible: true) == 1)
        #expect(UserMessageEditAccessibility.removesHiddenButtonFromAccessibilityTree == false)
    }
}
