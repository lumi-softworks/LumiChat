import Foundation
import PluginMessageSender
import ProviderMessage
import ProviderMessageSender

/// 输入框里的编辑会话：正在编辑的草稿，以及进入编辑前被收起的未发送草稿。
struct MessageEditSession: Equatable {
    let draft: MessageEditDraft
    let stashedText: String
    let stashedImageAttachments: [UserImageAttachment]
    let stashedFileAttachments: [UserFileAttachment]
    let stashedCollapsedBlocks: [CollapsedContentBlock]
}

/// 编辑失败时给用户看的文案。
enum MessageEditFailureMessage {
    @MainActor
    static func text(for error: any Error) -> String {
        switch error as? MessageEditError {
        case .cancelTimedOut?:
            pluginLocalization.string("The running turn didn't stop in time. Nothing was changed — please try again.")
        case .targetChanged?:
            pluginLocalization.string("This conversation received a new message, so this message can no longer be edited.")
        case .commitQueued?, .commitRejected?:
            pluginLocalization.string("The edited message couldn't be sent. Your edits are still here — please try again.")
        case .notEligible?:
            pluginLocalization.string("This message can no longer be edited.")
        case .noActiveEdit?, nil:
            pluginLocalization.string("No message is being edited.")
        }
    }
}
