#if os(macOS)
import Foundation
import Testing
@testable import PluginLLMProviderSettings

/// 设备信息卡片的硬件读取与格式化契约。
@Suite("设备信息")
struct LocalDeviceInfoTests {
    @Test("内存按 GiB 取整展示，与模型内存需求口径一致")
    func memoryUsesGiBRounding() {
        #expect(LocalDeviceInfo.formattedMemory(34_359_738_368) == "32 GB")
        #expect(LocalDeviceInfo.formattedMemory(51_539_607_552) == "48 GB")
        // 8 GiB 再加 1 字节应向上进位到 9 GB，而不是截断成 8 GB。
        #expect(LocalDeviceInfo.formattedMemory(8_589_934_593) == "9 GB")
    }

    @Test("当前设备能读到芯片、内存与磁盘")
    func currentDeviceReportsHardware() {
        let info = LocalDeviceInfo.current(cacheDirectory: nil)
        #expect(!info.chipName.isEmpty)
        #expect(info.physicalCoreCount > 0)
        #expect(info.memoryBytes > 0)
        #expect((info.availableDiskBytes ?? 0) > 0)
        #expect((info.totalDiskBytes ?? 0) > 0)
    }
}
#endif