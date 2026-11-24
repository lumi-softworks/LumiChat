import ProviderMessage
import SwiftUI

/// 编辑入口的无障碍标识符。
///
/// ZCode、ChatGPT 与旧版 chrome 三种呈现共用同一个标识符，UI 测试只认它。
enum UserMessageEditAccessibility {
    static let identifier = "lumi.user-message.edit"

    /// 按钮标签。
    static var label: String {
        pluginLocalization.string("Edit")
    }

    /// 行操作按钮不可见时的透明度。
    ///
    /// - Important: 未悬停 / 未聚焦时**只能**改透明度。调用方不得用 `hidden()`、
    ///   `accessibilityHidden(true)` 或条件移除来表达「当前不可见」——那会把按钮从
    ///   AX 树里摘掉，键盘用户与 UI 测试都找不到它。是否提供入口由
    ///   `UserMessageEditAction.isOffered` 决定，与悬停无关。
    static func opacity(isVisible: Bool) -> Double {
        isVisible ? 1 : 0
    }

    /// 不可见时是否移出 AX 树：否。
    static let removesHiddenButtonFromAccessibilityTree = false
}

/// 用户消息行的「编辑」动作与可提供性判定。
@MainActor
enum UserMessageEditAction {
    /// 这一行要不要提供编辑入口。
    ///
    /// 合成行（时间线事件、后台任务通知）不是普通用户消息，直接不提供；
    /// 其余交给编辑 Provider 按会话当前状态裁决。
    static func isOffered(_ message: Message, capability: any MessageRendererCapability) -> Bool {
        guard message.role == .user, !MessageTimelineEvent.isTimelineEvent(message) else { return false }
        return capability.canEditUserMessage(message, conversationID: message.conversationID)
    }

    /// 点击编辑：让输入框进入该消息的编辑模式。
    static func begin(_ message: Message, capability: any MessageRendererCapability) {
        capability.beginEditingUserMessage(message, conversationID: message.conversationID)
    }
}

/// 行级「编辑入口是否提供」的状态。
///
/// 可编辑性取决于整个会话的时间线与队列，判定并不便宜；行的 `body` 每次重绘
/// 都会求值，所以只在挂载、内容身份变化与悬停进入时刷新——悬停正是按钮变可见的时刻。
@MainActor
final class UserMessageEditOfferState: ObservableObject {
    @Published private(set) var isOffered = false

    func refresh(_ message: Message, capability: (any MessageRendererCapability)?) {
        guard let capability else {
            if isOffered { isOffered = false }
            return
        }
        let resolved = UserMessageEditAction.isOffered(message, capability: capability)
        guard resolved != isOffered else { return }
        isOffered = resolved
    }
}

/// 用户消息行的铅笔按钮。
///
/// - Important: 隐藏时由调用方只改透明度、不摘出 AX 树，键盘与 UI 测试才找得到它。
struct EditUserMessageButton: View {
    let capability: any MessageRendererCapability
    let message: Message
    var size: CGFloat = ZCodeUserBubbleStyle.copyButtonSize
    var iconSize: CGFloat = ZCodeUserBubbleStyle.copyButtonIconSize

    var body: some View {
        Button {
            UserMessageEditAction.begin(message, capability: capability)
        } label: {
            Image(systemName: "pencil.line")
                .font(.system(size: iconSize))
                .foregroundColor(.secondary)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(UserMessageEditAccessibility.identifier)
        .accessibilityLabel(UserMessageEditAccessibility.label)
        .help(UserMessageEditAccessibility.label)
    }
}
