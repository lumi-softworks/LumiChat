import AppKit
import PluginMessageSender
import ProviderMessage
import ProviderMessageSender
import SwiftUI
import Testing
@testable import PluginConversationInput

/// 输入框编辑模式：预填、暂存与恢复、编辑提交、失败保留、会话切换。
@MainActor
@Suite("输入框编辑会话")
struct EditSessionTests {
    private let conversationID = UUID()
    private let targetMessageID = UUID()

    private func makeDraft(
        content: String,
        images: [UserImageAttachment] = [],
        files: [UserFileAttachment] = [],
        blocks: [CollapsedContentBlock] = []
    ) -> MessageEditDraft {
        MessageEditDraft(
            targetMessageID: targetMessageID,
            conversationID: conversationID,
            content: content,
            imageAttachments: images,
            fileAttachments: files,
            collapsedBlocks: blocks
        )
    }

    private func image(_ data: String) -> UserImageAttachment {
        UserImageAttachment(mimeType: "image/png", base64Data: data)
    }

    private func file(_ name: String) -> UserFileAttachment {
        UserFileAttachment(fileName: name, mimeType: "text/plain", textContent: name)
    }

    /// 装配：能力层 + ViewModel + 生产同款编辑观察者。
    private func makeFixture() -> (SendActionBarTestCapability, ConversationInputViewModel, EditSessionObserver) {
        let capability = SendActionBarTestCapability()
        capability.selectedConversationID = conversationID
        let viewModel = ConversationInputViewModel(capability: capability)
        let observer = EditSessionObserver(capability: capability, viewModel: viewModel)
        return (capability, viewModel, observer)
    }

    // MARK: - 预填 / 暂存 / 恢复

    @Test("进入编辑：暂存未发送草稿，输入框换成被编辑消息的正文、附件与折叠块")
    func beginEditingPrefillsDraftAndStashesCurrentInput() {
        let (capability, viewModel, observer) = makeFixture()
        defer { observer.cancel() }
        capability.text = "unsent draft"
        capability.addImageAttachment(image("UNSSENT"))
        capability.addFileAttachment(file("unsent.txt"))
        let stashedBlocks = [CollapsedContentBlock(start: 0, length: 2, title: "Old", systemImage: "doc")]
        capability.collapsedBlocks = stashedBlocks

        let block = CollapsedContentBlock(start: 4, length: 3, title: "Selection", systemImage: "chevron.left.forwardslash.chevron.right")
        let draftImage = image("DRAFT")
        let draftFile = file("draft.txt")
        capability.emitEditingEvent(.began(makeDraft(
            content: "say Selection now",
            images: [draftImage],
            files: [draftFile],
            blocks: [block]
        )))

        #expect(viewModel.editSession?.draft.targetMessageID == targetMessageID)
        #expect(viewModel.editSession?.stashedText == "unsent draft")
        #expect(viewModel.text == "say Selection now")
        #expect(capability.text == "say Selection now")
        #expect(capability.pendingImageAttachments.map(\.id) == [draftImage.id])
        #expect(capability.pendingFileAttachments.map(\.id) == [draftFile.id])
        #expect(capability.collapsedBlocks == [block])
        #expect(viewModel.chipRestoration == EditorChipRestoration(text: "say Selection now", blocks: [block]))
        #expect(capability.isInputFocused)
        #expect(capability.inputCursorPosition == "say Selection now".count)
        #expect(capability.editSession == viewModel.editSession)
    }

    @Test("编辑结束：恢复编辑前的正文、附件与折叠块，并清空编辑会话")
    func endingEditingRestoresStashedDraft() {
        let (capability, viewModel, observer) = makeFixture()
        defer { observer.cancel() }
        let stashedImage = image("UNSSENT")
        let stashedFile = file("unsent.txt")
        let stashedBlocks = [CollapsedContentBlock(start: 0, length: 6, title: "Paste", systemImage: "doc.on.clipboard")]
        capability.text = "Pasted body follows"
        capability.addImageAttachment(stashedImage)
        capability.addFileAttachment(stashedFile)
        capability.collapsedBlocks = stashedBlocks
        capability.emitEditingEvent(.began(makeDraft(content: "original message")))
        #expect(capability.text == "original message")

        capability.emitEditingEvent(.ended(conversationID: conversationID))

        #expect(viewModel.editSession == nil)
        #expect(capability.editSession == nil)
        #expect(capability.text == "Pasted body follows")
        #expect(viewModel.text == "Pasted body follows")
        #expect(capability.pendingImageAttachments.map(\.id) == [stashedImage.id])
        #expect(capability.pendingFileAttachments.map(\.id) == [stashedFile.id])
        #expect(capability.collapsedBlocks == stashedBlocks)
        #expect(viewModel.chipRestoration == EditorChipRestoration(text: "Pasted body follows", blocks: stashedBlocks))
    }

    @Test("其他会话的结束事件不影响当前编辑会话")
    func endedEventForOtherConversationIsIgnored() {
        let (capability, viewModel, observer) = makeFixture()
        defer { observer.cancel() }
        capability.emitEditingEvent(.began(makeDraft(content: "original message")))

        capability.emitEditingEvent(.ended(conversationID: UUID()))

        #expect(viewModel.editSession != nil)
        #expect(capability.text == "original message")
    }

    @Test("取消编辑：转给编辑 Provider，由它发布结束事件并恢复草稿")
    func cancelEditingRestoresStash() {
        let (capability, viewModel, observer) = makeFixture()
        defer { observer.cancel() }
        capability.text = "unsent draft"
        capability.emitEditingEvent(.began(makeDraft(content: "original message")))

        viewModel.cancelEditing()

        #expect(capability.cancelEditingCount == 1)
        #expect(viewModel.editSession == nil)
        #expect(capability.text == "unsent draft")
    }

    // MARK: - 提交

    @Test("编辑模式下发送只走编辑提交，普通发送路径不被调用")
    func submitUsesEditPathExactlyOnce() async throws {
        let (capability, viewModel, observer) = makeFixture()
        defer { observer.cancel() }
        capability.editCommit = MessageSendCommit(conversationID: conversationID, userMessageID: UUID())
        capability.emitEditingEvent(.began(makeDraft(content: "original message")))
        capability.emitText("edited message")

        viewModel.send()
        await awaitSettle()

        #expect(capability.submittedEdits.count == 1)
        let submitted = try #require(capability.submittedEdits.first)
        #expect(submitted.targetMessageID == targetMessageID)
        #expect(submitted.conversationID == conversationID)
        #expect(submitted.content == "edited message")
        #expect(capability.commits.isEmpty)
        #expect(capability.backgroundCommits.isEmpty)
        #expect(capability.startedCommits.count == 1)
        #expect(!capability.isCommittingDraft)
    }

    @Test("提交成功后编辑会话结束，输入框回到编辑前的草稿")
    func successfulSubmitEndsEditingAndRestoresStash() async throws {
        let (capability, viewModel, observer) = makeFixture()
        defer { observer.cancel() }
        capability.text = "unsent draft"
        capability.emitEditingEvent(.began(makeDraft(content: "original message")))

        viewModel.send()
        await awaitSettle()

        #expect(viewModel.editSession == nil)
        #expect(capability.text == "unsent draft")
        #expect(viewModel.chipRestoration == nil)
    }

    @Test("等待回合停下的窗口里重复触发发送不会重复提交")
    func repeatedSendWhileSubmittingIsIgnored() async throws {
        let (capability, viewModel, observer) = makeFixture()
        defer { observer.cancel() }
        capability.holdsEditSubmits = true
        capability.emitEditingEvent(.began(makeDraft(content: "original message")))

        viewModel.send()
        viewModel.send()
        await awaitSettle()
        // 提交被挂起期间，输入框里的正文还在，但再次发送必须被忽略。
        #expect(capability.submittedEdits.count == 1)
        #expect(!viewModel.canSend)
        viewModel.send()
        #expect(capability.submittedEdits.count == 1)

        capability.releaseEditSubmits()
        await awaitSettle()

        #expect(capability.submittedEdits.count == 1)
        #expect(viewModel.editSession == nil)
    }

    @Test("编辑模式下发送按钮只转交给输入框 ViewModel")
    func actionBarForwardsSendWhileEditing() async throws {
        let (capability, viewModel, observer) = makeFixture()
        defer { observer.cancel() }
        capability.editCommit = MessageSendCommit(conversationID: conversationID, userMessageID: UUID())
        let actionBar = SendActionBarViewModel(capability: capability)
        var forwarded = 0
        actionBar.onEditSubmit = {
            forwarded += 1
            viewModel.send()
        }
        capability.emitEditingEvent(.began(makeDraft(content: "original message")))

        actionBar.send()
        await awaitSettle()

        #expect(forwarded == 1)
        #expect(capability.submittedEdits.count == 1)
        #expect(capability.commits.isEmpty)
    }

    // MARK: - 失败

    @Test("提交失败：保留编辑后的正文与附件，显示错误，仍处于编辑模式")
    func submitErrorKeepsDraftAndEditSession() async throws {
        let (capability, viewModel, observer) = makeFixture()
        defer { observer.cancel() }
        capability.emitEditingEvent(.began(makeDraft(content: "original message")))
        let addedImage = image("ADDED")
        capability.addImageAttachment(addedImage)
        capability.emitText("edited message")
        capability.editError = MessageEditError.targetChanged

        viewModel.send()
        await awaitSettle()

        #expect(capability.errorMessage == MessageEditFailureMessage.text(for: MessageEditError.targetChanged))
        #expect(viewModel.errorMessage == capability.errorMessage)
        #expect(viewModel.editSession != nil)
        #expect(capability.editSession != nil)
        #expect(capability.text == "edited message")
        #expect(capability.pendingImageAttachments.map(\.id) == [addedImage.id])
        #expect(!capability.isCommittingDraft)
        #expect(capability.startedCommits.isEmpty)
        #expect(!MessageEditFailureMessage.text(for: MessageEditError.targetChanged).isEmpty)
    }

    @Test("失败后重试再次走编辑提交")
    func retryAfterErrorSubmitsAgain() async throws {
        let (capability, viewModel, observer) = makeFixture()
        defer { observer.cancel() }
        capability.editError = MessageEditError.cancelTimedOut
        capability.emitEditingEvent(.began(makeDraft(content: "original message")))

        viewModel.send()
        await awaitSettle()
        capability.editError = nil
        viewModel.send()
        await awaitSettle()

        #expect(capability.submittedEdits.count == 2)
        #expect(viewModel.editSession == nil)
        #expect(capability.errorMessage == nil)
    }

    // MARK: - 会话切换

    @Test("切换会话结束编辑：先恢复编辑前草稿，再按常规切换清空输入框")
    func conversationSwitchEndsEditingAndClearsInput() async throws {
        let (capability, viewModel, observer) = makeFixture()
        defer { observer.cancel() }
        let conversationObserver = ActionBarConversationObserver(capability: capability, viewModel: viewModel)
        defer { conversationObserver.cancel() }
        let stashedImage = image("UNSSENT")
        capability.text = "unsent draft"
        capability.addImageAttachment(stashedImage)
        capability.emitEditingEvent(.began(makeDraft(content: "original message")))
        #expect(capability.text == "original message")

        capability.emitSelectedConversation(UUID())
        await awaitSettle()

        #expect(capability.cancelEditingCount == 1)
        #expect(viewModel.editSession == nil)
        #expect(viewModel.chipRestoration == nil)
        #expect(capability.text.isEmpty)
        #expect(capability.pendingImageAttachments.isEmpty)
        #expect(capability.errorMessage == nil)
    }

    // MARK: - 附件

    @Test("编辑期间增删附件，提交的是提交瞬间的附件集合")
    func attachmentChangesWhileEditingReachSubmitEdit() async throws {
        let (capability, viewModel, observer) = makeFixture()
        defer { observer.cancel() }
        let originalImage = image("ORIGINAL")
        let originalFile = file("original.txt")
        capability.emitEditingEvent(.began(makeDraft(
            content: "original message",
            images: [originalImage],
            files: [originalFile]
        )))
        let addedImage = image("ADDED")
        let addedFile = file("added.txt")

        capability.removeImageAttachment(id: originalImage.id)
        capability.removeFileAttachment(id: originalFile.id)
        capability.addImageAttachment(addedImage)
        capability.addFileAttachment(addedFile)
        viewModel.send()
        await awaitSettle()

        let submitted = try #require(capability.submittedEdits.first)
        #expect(submitted.imageAttachments.map(\.id) == [addedImage.id])
        #expect(submitted.fileAttachments.map(\.id) == [addedFile.id])
    }

    @Test("去掉全部附件后只提交正文")
    func removingAllAttachmentsSubmitsTextOnly() async throws {
        let (capability, viewModel, observer) = makeFixture()
        defer { observer.cancel() }
        let originalImage = image("ORIGINAL")
        capability.emitEditingEvent(.began(makeDraft(content: "original message", images: [originalImage])))

        capability.removeImageAttachment(id: originalImage.id)
        viewModel.send()
        await awaitSettle()

        let submitted = try #require(capability.submittedEdits.first)
        #expect(submitted.imageAttachments.isEmpty)
        #expect(submitted.fileAttachments.isEmpty)
    }

    // MARK: - 折叠块还原

    @Test("按折叠块生成的富文本拍平后与原草稿一致（chip 还原不改正文与区间）")
    func restoredChipsFlattenBackToTheSameDraft() throws {
        let text = "before PASTED-BODY middle Selection.swift after"
        let blocks = [
            CollapsedContentBlock(start: 7, length: 11, title: "Pasted text", systemImage: "doc.on.clipboard"),
            CollapsedContentBlock(start: 25, length: 14, title: "Selection.swift", systemImage: "chevron.left.forwardslash.chevron.right"),
        ]

        let attributed = ChatInputEditorView.attributedContent(
            text: text,
            blocks: blocks,
            font: NSFont.systemFont(ofSize: 14),
            palette: .fallback
        )
        let result = ChatInputEditorView.flattenedContent(from: NSTextStorage(attributedString: attributed))

        #expect(result.text == text)
        #expect(result.hasAttachments)
        #expect(result.blocks.map(\.start) == blocks.map(\.start))
        #expect(result.blocks.map(\.length) == blocks.map(\.length))
        // chip 标题会在原标题后追加字数 / 行数摘要。
        #expect(zip(result.blocks, blocks).allSatisfy { $0.title.hasPrefix($1.title) })
    }

    @Test("区间越界的折叠块按纯文本保留，不会丢字")
    func outOfRangeBlocksStayAsPlainText() {
        let attributed = ChatInputEditorView.attributedContent(
            text: "short",
            blocks: [CollapsedContentBlock(start: 2, length: 50, title: "Broken", systemImage: "doc")],
            font: NSFont.systemFont(ofSize: 14),
            palette: .fallback
        )
        let result = ChatInputEditorView.flattenedContent(from: NSTextStorage(attributedString: attributed))

        #expect(result.text == "short")
        #expect(result.blocks.isEmpty)
    }
}
