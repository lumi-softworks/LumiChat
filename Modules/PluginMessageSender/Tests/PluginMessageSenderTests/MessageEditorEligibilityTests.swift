import Foundation
import KernelCore
import ProviderAgentLoop
import ProviderConversation
import ProviderMessage
import ProviderMessageSender
import Testing
@testable import PluginMessageSender

@Suite("MessageEditor 可编辑性判定")
@MainActor
struct MessageEditorEligibilityTests {

    // MARK: - 最新真实用户消息

    @Test("最新的一条真实用户消息可编辑")
    func latestRealUserMessageIsEditable() throws {
        let fixture = try EditFixture()
        let seeded = try fixture.seedTwoTurns()

        #expect(fixture.editor.eligibility(for: seeded.target, in: fixture.conversationID) == .allowed)
        // 更早的用户消息与助手消息都不可编辑。
        #expect(fixture.editor.eligibility(for: seeded.olderUser, in: fixture.conversationID) == .notLatestRealUserMessage)
        let assistant = try #require(fixture.messages.messages(for: fixture.conversationID).first { $0.role == .assistant })
        #expect(fixture.editor.eligibility(for: assistant, in: fixture.conversationID) == .notLatestRealUserMessage)
    }

    @Test("最新用户消息之后的时间线卡片不妨碍编辑")
    func timelineEventAfterTargetKeepsItEditable() throws {
        let fixture = try EditFixture()
        let target = fixture.insert(.user, content: "question", turnID: UUID())
        fixture.insert(.user, content: "", metadata: [
            MessageTimelineEvent.metadataKey: MessageTimelineEvent.finder,
        ])

        #expect(fixture.editor.eligibility(for: target, in: fixture.conversationID) == .allowed)
    }

    @Test("最新用户消息之后的后台任务通知不妨碍编辑，通知本身不可编辑")
    func backgroundNotificationAfterTargetKeepsItEditable() throws {
        let fixture = try EditFixture()
        let target = fixture.insert(.user, content: "question", turnID: UUID())
        let notification = fixture.insert(.user, content: "background task finished", metadata: [
            MessageEditor.backgroundNotificationMetadataKey: "true",
        ])

        #expect(fixture.editor.eligibility(for: target, in: fixture.conversationID) == .allowed)
        #expect(fixture.editor.eligibility(for: notification, in: fixture.conversationID) == .notLatestRealUserMessage)
    }

    @Test("只有后台任务通知的会话没有可编辑的消息")
    func notificationOnlyConversationIsNotEditable() throws {
        let fixture = try EditFixture()
        let notification = fixture.insert(.user, content: "background task finished", metadata: [
            MessageEditor.backgroundNotificationMetadataKey: "true",
        ])

        #expect(fixture.editor.eligibility(for: notification, in: fixture.conversationID) == .notLatestRealUserMessage)
        #expect(fixture.editor.beginEditing(message: notification, in: fixture.conversationID) == false)
    }

    @Test("其它会话里的消息不可编辑")
    func messageFromAnotherConversationIsNotEditable() throws {
        let fixture = try EditFixture()
        let seeded = try fixture.seedTwoTurns()
        let otherConversation = try fixture.conversations.createConversation(
            title: nil, projectPath: nil, providerID: nil, modelName: nil
        )

        #expect(fixture.editor.eligibility(for: seeded.target, in: otherConversation) == .notLatestRealUserMessage)
    }

    // MARK: - 抑制、排队与附件读取

    @Test("自动回复被抑制的会话不可编辑（ACP 托管 / 子代理会话）")
    func suppressedConversationIsNotEditable() throws {
        let fixture = try EditFixture()
        let seeded = try fixture.seedTwoTurns()
        fixture.agentLoop.suppressed.insert(fixture.conversationID)

        #expect(fixture.editor.eligibility(for: seeded.target, in: fixture.conversationID) == .autoReplySuppressed)
        #expect(fixture.editor.beginEditing(message: seeded.target, in: fixture.conversationID) == false)
    }

    @Test("抑制判定先于排队、附件读取与空内容判定")
    func suppressionTakesPrecedenceOverOtherReasons() throws {
        let fixture = try EditFixture()
        let target = fixture.insert(.user, content: "   ")
        fixture.sender.beginAttachmentRead()
        fixture.agentLoop.suppressed.insert(fixture.conversationID)
        _ = queuePendingMessage(in: fixture)

        #expect(fixture.editor.eligibility(for: target, in: fixture.conversationID) == .autoReplySuppressed)
    }

    @Test("还有排队待发消息时不可编辑，排空后恢复")
    func queuedMessagesBlockEditing() throws {
        let fixture = try EditFixture()
        let seeded = try fixture.seedTwoTurns()
        let id = fixture.conversationID
        fixture.agentLoop.states[id] = .running
        _ = try fixture.sender.commitUserMessage("queued", conversationID: id)
        #expect(fixture.sender.pendingMessages(for: id).count == 1)

        #expect(fixture.editor.eligibility(for: seeded.target, in: id) == .queuedMessagesPending)
        #expect(fixture.editor.beginEditing(message: seeded.target, in: id) == false)

        fixture.agentLoop.states[id] = .idle
        fixture.sender.handleAgentLoopEvent(.cancelled(conversationID: id, turnID: UUID()))
        #expect(fixture.editor.eligibility(for: seeded.target, in: id) != .queuedMessagesPending)
    }

    @Test("附件仍在读取时不可编辑，读取结束后恢复")
    func inFlightAttachmentReadsBlockEditing() throws {
        let fixture = try EditFixture()
        let seeded = try fixture.seedTwoTurns()
        let id = fixture.conversationID
        fixture.sender.beginAttachmentRead()

        #expect(fixture.editor.eligibility(for: seeded.target, in: id) == .attachmentsStillLoading)
        #expect(fixture.editor.beginEditing(message: seeded.target, in: id) == false)

        fixture.sender.endAttachmentRead()
        #expect(fixture.editor.eligibility(for: seeded.target, in: id) == .allowed)
    }

    // MARK: - 编辑会话与空内容

    @Test("编辑期间再次进入返回 alreadyEditing")
    func alreadyEditingIsReported() throws {
        let fixture = try EditFixture()
        let seeded = try fixture.seedTwoTurns()
        #expect(fixture.editor.beginEditing(message: seeded.target, in: fixture.conversationID))

        #expect(fixture.editor.eligibility(for: seeded.target, in: fixture.conversationID) == .alreadyEditing)
        #expect(fixture.editor.beginEditing(message: seeded.target, in: fixture.conversationID) == false)
    }

    @Test("正文为空且没有附件的用户消息不可编辑")
    func emptyContentIsNotEditable() throws {
        let fixture = try EditFixture()
        let target = fixture.insert(.user, content: "  \n ")

        #expect(fixture.editor.eligibility(for: target, in: fixture.conversationID) == .emptyContent)
    }

    // MARK: - 会话事件

    @Test("开始编辑发布带预填内容的 began，取消发布 ended 且不改时间线")
    func beginAndCancelPublishLifecycleEvents() throws {
        let fixture = try EditFixture()
        let seeded = try fixture.seedTwoTurns()
        var events: [MessageEditingEvent] = []
        let handle = fixture.editor.addObserver { events.append($0) }
        defer { handle.cancel() }
        let before = fixture.contents()

        #expect(fixture.editor.beginEditing(message: seeded.target, in: fixture.conversationID))

        guard case .began(let draft)? = events.first else {
            Issue.record("应先发布 began")
            return
        }
        #expect(draft == MessageEditDraft(
            targetMessageID: seeded.target.id,
            conversationID: fixture.conversationID,
            content: "second question"
        ))
        #expect(fixture.editor.activeEdit == draft)

        fixture.editor.cancelEditing(in: fixture.conversationID)

        #expect(events.count == 2)
        guard case .ended(let endedConversationID)? = events.last else {
            Issue.record("应发布 ended")
            return
        }
        #expect(endedConversationID == fixture.conversationID)
        #expect(fixture.editor.activeEdit == nil)
        #expect(fixture.contents() == before)
    }

    @Test("取消其它会话的编辑不发布事件")
    func cancellingOtherConversationIsIgnored() throws {
        let fixture = try EditFixture()
        let seeded = try fixture.seedTwoTurns()
        var events: [MessageEditingEvent] = []
        let handle = fixture.editor.addObserver { events.append($0) }
        defer { handle.cancel() }
        #expect(fixture.editor.beginEditing(message: seeded.target, in: fixture.conversationID))
        events.removeAll()

        fixture.editor.cancelEditing(in: UUID())

        #expect(events.isEmpty)
        #expect(fixture.editor.activeEdit != nil)
    }

    @Test("附件或折叠块元数据损坏时退化为纯文本草稿")
    func corruptMetadataDegradesToTextOnly() throws {
        let fixture = try EditFixture()
        let target = fixture.insert(.user, content: "question", metadata: [
            UserAttachmentMetadata.imageAttachmentsKey: "{not json",
            CollapsedContentBlockMetadata.collapsedBlocksKey: "]]",
        ])

        #expect(fixture.editor.eligibility(for: target, in: fixture.conversationID) == .allowed)
        #expect(fixture.editor.beginEditing(message: target, in: fixture.conversationID))
        let draft = try #require(fixture.editor.activeEdit)
        #expect(draft.content == "question")
        #expect(draft.imageAttachments.isEmpty)
        #expect(draft.fileAttachments.isEmpty)
        #expect(draft.collapsedBlocks.isEmpty)
    }

    @Test("取消编辑后观察者不再收到事件")
    func cancelledObserverStopsReceivingEvents() throws {
        let fixture = try EditFixture()
        let seeded = try fixture.seedTwoTurns()
        var events: [MessageEditingEvent] = []
        let handle = fixture.editor.addObserver { events.append($0) }
        handle.cancel()

        #expect(fixture.editor.beginEditing(message: seeded.target, in: fixture.conversationID))

        #expect(events.isEmpty)
    }

    // MARK: - 装配

    @Test("onBoot 注册 MessageEditingProviding；缺少工具管理器时同样可用")
    func pluginRegistersEditingProvider() throws {
        let kernel = KernelCoreContainer()
        let conversations = DefaultConversationManager()
        try kernel.registerProvider((any ConversationManaging).self, conversations)
        let messages = DefaultMessageManager()
        try kernel.registerProvider((any MessageManaging).self, messages)
        try kernel.registerProvider((any AgentLoopProviding).self, StubAgentLoop(messages: messages))

        let plugin = MessageSenderPlugin()
        plugin.pendingQueueStore = PendingQueueStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-queue-\(UUID().uuidString).json"))
        try kernel.start(plugins: [plugin])

        let editing = kernel.resolveProvider((any MessageEditingProviding).self)
        #expect(editing is MessageEditor)
        #expect(kernel.isProvider((any MessageEditingProviding).self, ownedByPlugin: plugin.id))
        let conversationID = try conversations.createConversation(
            title: nil, projectPath: nil, providerID: nil, modelName: nil
        )
        let message = Message(conversationID: conversationID, role: .user, content: "hello")
        messages.insertMessage(message, to: conversationID)
        #expect(editing?.eligibility(for: message, in: conversationID) == .allowed)
    }

    // MARK: - Helpers

    private func queuePendingMessage(in fixture: EditFixture) -> MessageSendCommit? {
        fixture.agentLoop.states[fixture.conversationID] = .running
        return try? fixture.sender.commitUserMessage("queued", conversationID: fixture.conversationID)
    }
}
