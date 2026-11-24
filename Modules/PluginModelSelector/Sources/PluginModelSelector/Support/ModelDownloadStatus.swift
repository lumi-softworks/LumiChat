import KitLLM

/// 选择器里单个本地模型的下载状态。
///
/// 只有实现 `LLMModelDownloadProviding` 的供应商才会得到 `.unavailable`
/// 以外的值；远程供应商不展示下载角标。
enum ModelDownloadStatus: Equatable {
    /// 供应商不支持模型下载（远程供应商或未实现下载能力）。
    case unavailable
    case notDownloaded
    case downloading(progress: Double)
    case paused(progress: Double)
    case downloaded
    case failed

    /// 由下载器快照推导指定模型的状态。
    ///
    /// 下载器同一时刻只处理一个模型（`state.modelID`），因此进度与失败只归属
    /// 该模型；其余模型一律按 `downloadedModelIDs` 判断是否已落盘。
    init(state: LLMModelDownloadState, modelID: String) {
        switch state.status {
        case .downloading where state.modelID == modelID:
            self = .downloading(progress: Self.clamp(state.progress.fractionCompleted))
        case .paused where state.modelID == modelID:
            self = .paused(progress: Self.clamp(state.progress.fractionCompleted))
        case .failed where state.modelID == modelID:
            self = .failed
        default:
            self = state.downloadedModelIDs.contains(modelID) ? .downloaded : .notDownloaded
        }
    }

    /// 下载进度百分比文案（仅下载中/暂停时有值）。
    var percentText: String? {
        switch self {
        case .downloading(let progress), .paused(let progress):
            return "\(Int((progress * 100).rounded()))%"
        default:
            return nil
        }
    }

    /// 进度来自外部下载器，防御 0...1 之外的脏值。
    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}