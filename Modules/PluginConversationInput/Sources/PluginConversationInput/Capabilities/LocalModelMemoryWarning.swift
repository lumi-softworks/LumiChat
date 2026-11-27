import Foundation
import KitLLM
import SwiftUI

/// 大内存本地模型的发送前二次确认信息。
///
/// 由发送链路在提交用户消息前判定；`nil` 表示无需确认，消息直接提交。
struct LocalModelMemoryWarning: Equatable, Sendable {
    /// 模型展示名。
    let modelName: String
    /// 模型声明可运行的最低物理内存（字节）。
    let minimumMemoryBytes: Int64
}

extension LocalModelMemoryWarning {
    /// 触发确认的内存占比线：模型声明的最低物理内存达到本机一半时提醒。
    ///
    /// KV 缓存、系统与其他 App 的占用意味着一旦越线，交换内存几乎不可避免，
    /// 表现就是用户感知到的「电脑卡到几乎不能操作」。
    static let physicalMemoryRatio: Double = 0.5

    /// 纯判定：是否该在发送前弹二次确认。
    ///
    /// - Parameters:
    ///   - providerInfo: 模型所属供应商；云模型没有加载开销，直接放行。
    ///   - modelInfo: 模型元数据；`minimumMemoryBytes` 未知时不提醒。
    ///   - physicalMemoryBytes: 本机物理内存。
    ///   - isModelResident: 模型是否已驻留内存；`true` 表示不会再触发加载，
    ///     不必重复打扰，`nil`（未知）按保守策略仍提醒。
    static func warningIfHeavy(
        providerInfo: LLMProviderInfo,
        modelInfo: LLMModelInfo,
        physicalMemoryBytes: Int64,
        isModelResident: Bool?
    ) -> LocalModelMemoryWarning? {
        guard providerInfo.isLocal,
              let minimumBytes = modelInfo.minimumMemoryBytes,
              minimumBytes > 0,
              Double(minimumBytes) >= Double(physicalMemoryBytes) * physicalMemoryRatio,
              isModelResident != true
        else { return nil }
        return LocalModelMemoryWarning(
            modelName: modelInfo.displayName,
            minimumMemoryBytes: minimumBytes
        )
    }

    /// 确认弹窗标题。
    var titleText: String {
        pluginLocalization.string("This model may slow down your Mac")
    }

    /// 确认弹窗正文：模型名与内存需求插值后的本地化文案。
    var messageText: String {
        String(
            format: pluginLocalization.string(
                "Loading %@ takes about %@ of memory, which may make your Mac feel sluggish."
            ),
            modelName,
            ByteCountFormatter.string(fromByteCount: minimumMemoryBytes, countStyle: .memory)
        )
    }
}

/// 大内存本地模型的发送确认弹窗，两条发送入口视图共用。
///
/// `warning` 绑定到所属 ViewModel 的告警状态；任何关闭路径（取消按钮、
/// Esc、点击弹窗外部）都转给 `onCancel`，由 ViewModel 清掉告警与发送
/// 快照——只把 `warning` 置空是不够的，快照还挂在 ViewModel 上。
private struct LocalModelMemoryWarningDialog: ViewModifier {
    @Binding var warning: LocalModelMemoryWarning?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            warning?.titleText ?? "",
            isPresented: Binding(
                get: { warning != nil },
                set: { if !$0 { onCancel() } }
            ),
            titleVisibility: .visible
        ) {
            Button(pluginLocalization.string("Send Anyway"), action: onConfirm)
                .accessibilityIdentifier(SendActionBarAccessibility.localModelConfirmButton)
            Button(pluginLocalization.string("Cancel"), role: .cancel, action: onCancel)
                .accessibilityIdentifier(SendActionBarAccessibility.localModelCancelButton)
        } message: {
            if let warning {
                Text(warning.messageText)
            }
        }
    }
}

extension View {
    /// 挂载发送前的大模型二次确认弹窗。
    func localModelMemoryWarningDialog(
        warning: Binding<LocalModelMemoryWarning?>,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        modifier(LocalModelMemoryWarningDialog(warning: warning, onConfirm: onConfirm, onCancel: onCancel))
    }
}
