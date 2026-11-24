import LumiUI
import SwiftUI

/// 编辑模式横幅：说明输入框里是被编辑的消息，并提供取消入口。
struct EditSessionBanner: View {
    @LumiTheme private var theme

    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil.line")
                .font(.caption)
                .foregroundColor(theme.textSecondary)

            Text(pluginLocalization.string("Editing message"))
                .font(.caption)
                .foregroundColor(theme.textPrimary)

            Spacer()

            Button(action: onCancel) {
                Text(pluginLocalization.string("Cancel"))
                    .font(.caption)
                    .foregroundColor(theme.textPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("lumi.conversation-input.edit-cancel")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(theme.textPrimary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lumi.conversation-input.edit-banner")
    }
}
