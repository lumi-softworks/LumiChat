#if os(macOS)
import LumiUI
import SwiftUI

/// 本地模型页顶部的设备概况卡片。
///
/// 下载前先让用户看到当前硬件：内存决定能运行多大的模型，
/// 可用磁盘决定还能放下多少模型。
@MainActor
struct DeviceInfoSection: View {
    @LumiTheme private var theme

    let info: LocalDeviceInfo

    var body: some View {
        AppSettingSection(
            title: pluginLocalization.string("设备信息"),
            footer: pluginLocalization.string("内存决定能运行多大的模型，可用磁盘决定还能下载多少模型。")
        ) {
            VStack(spacing: 0) {
                AppSettingRow(
                    title: pluginLocalization.string("芯片"),
                    description: String(
                        format: pluginLocalization.string("%lld 核 CPU"),
                        Int64(info.physicalCoreCount)
                    ),
                    icon: "cpu"
                ) {
                    valueText(info.chipName)
                }

                rowDivider

                AppSettingRow(
                    title: pluginLocalization.string("统一内存"),
                    icon: "memorychip"
                ) {
                    valueText(LocalDeviceInfo.formattedMemory(info.memoryBytes))
                }

                if let availableDiskBytes = info.availableDiskBytes {
                    rowDivider
                    AppSettingRow(
                        title: pluginLocalization.string("可用磁盘"),
                        description: info.totalDiskBytes.map {
                            String(
                                format: pluginLocalization.string("共 %@"),
                                LocalDeviceInfo.formattedDisk($0)
                            )
                        },
                        icon: "internaldrive"
                    ) {
                        valueText(LocalDeviceInfo.formattedDisk(availableDiskBytes))
                    }
                }
            }
        }
    }

    private func valueText(_ value: String) -> some View {
        Text(value)
            .font(.appBody)
            .foregroundStyle(theme.textSecondary)
    }

    private var rowDivider: some View {
        Divider()
            .padding(.vertical, 8)
    }
}
#endif