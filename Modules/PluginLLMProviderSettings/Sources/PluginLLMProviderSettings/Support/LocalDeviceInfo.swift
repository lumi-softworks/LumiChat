#if os(macOS)
import Darwin
import Foundation

/// 运行本地模型所依赖的硬件概况。
///
/// 只保留与「能否下载 / 运行模型」直接相关的信息：芯片、CPU 核数、
/// 统一内存，以及模型缓存所在卷的剩余空间。
struct LocalDeviceInfo: Equatable, Sendable {
    let chipName: String
    let physicalCoreCount: Int
    let memoryBytes: Int64
    let availableDiskBytes: Int64?
    let totalDiskBytes: Int64?

    /// 读取当前设备信息；磁盘空间取模型缓存所在卷（目录不存在时回退到用户目录）。
    static func current(cacheDirectory: URL?) -> LocalDeviceInfo {
        let volumeURL = cacheDirectory ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let values = try? volumeURL.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeTotalCapacityKey,
        ])
        return LocalDeviceInfo(
            chipName: chipName(),
            physicalCoreCount: ProcessInfo.processInfo.processorCount,
            memoryBytes: Int64(clamping: ProcessInfo.processInfo.physicalMemory),
            availableDiskBytes: values?.volumeAvailableCapacityForImportantUsage
                ?? values?.volumeAvailableCapacity.map(Int64.init),
            totalDiskBytes: values?.volumeTotalCapacity.map(Int64.init)
        )
    }

    /// 内存按 GiB 取整，与模型「最低 %lld GB 内存」口径一致；GB 是通用单位，不随界面语言变化。
    static func formattedMemory(_ bytes: Int64) -> String {
        let gib = (bytes + 1_073_741_823) / 1_073_741_824
        return String(format: "%lld GB", gib)
    }

    static func formattedDisk(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func chipName() -> String {
        if let name = sysctlString("machdep.cpu.brand_string") {
            return name
        }
        #if arch(arm64)
        return "Apple Silicon"
        #else
        return "Intel"
        #endif
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let value = String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
#endif