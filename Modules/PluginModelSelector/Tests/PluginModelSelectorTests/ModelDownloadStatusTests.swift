import Combine
import Foundation
import KitLLM
import ProviderLLMManager
import Testing
@testable import PluginModelSelector

/// 模型选择器里的本地模型下载状态。
///
/// 选择器本身不管理下载，只把供应商 `LLMModelDownloadProviding` 的快照映射成
/// 每行的角标；下载动作仍在设置页或首次发送时触发。
@MainActor
struct ModelDownloadStatusTests {

    // MARK: - 状态映射

    @Test("下载中只归属当前模型，其余模型按已落盘集合判断")
    func downloadingOnlyAppliesToActiveModel() {
        let state = LLMModelDownloadState(
            status: .downloading,
            modelID: "m2",
            progress: .init(fractionCompleted: 0.42),
            downloadedModelIDs: ["m1"]
        )

        #expect(ModelDownloadStatus(state: state, modelID: "m1") == .downloaded)
        #expect(ModelDownloadStatus(state: state, modelID: "m2") == .downloading(progress: 0.42))
        #expect(ModelDownloadStatus(state: state, modelID: "m3") == .notDownloaded)
        #expect(ModelDownloadStatus(state: state, modelID: "m2").percentText == "42%")
    }

    @Test("暂停只标记当前模型，其他模型不受影响")
    func pausedOnlyAppliesToActiveModel() {
        let state = LLMModelDownloadState(
            status: .paused,
            modelID: "m2",
            progress: .init(fractionCompleted: 0.7),
            downloadedModelIDs: ["m1"]
        )

        #expect(ModelDownloadStatus(state: state, modelID: "m2") == .paused(progress: 0.7))
        #expect(ModelDownloadStatus(state: state, modelID: "m1") == .downloaded)
        #expect(ModelDownloadStatus(state: state, modelID: "m3") == .notDownloaded)
    }

    @Test("失败只标记当前模型，已下载模型保持已下载")
    func failedOnlyAppliesToActiveModel() {
        let state = LLMModelDownloadState(
            status: .failed("网络中断"),
            modelID: "m2",
            downloadedModelIDs: ["m1"]
        )

        #expect(ModelDownloadStatus(state: state, modelID: "m2") == .failed)
        #expect(ModelDownloadStatus(state: state, modelID: "m1") == .downloaded)
        #expect(ModelDownloadStatus(state: state, modelID: "m3") == .notDownloaded)
    }

    @Test("异常进度被限制在 0...1")
    func progressIsClamped() {
        let over = LLMModelDownloadState(
            status: .downloading,
            modelID: "m1",
            progress: .init(fractionCompleted: 1.8)
        )
        let under = LLMModelDownloadState(
            status: .paused,
            modelID: "m1",
            progress: .init(fractionCompleted: -0.4)
        )

        #expect(ModelDownloadStatus(state: over, modelID: "m1") == .downloading(progress: 1))
        #expect(ModelDownloadStatus(state: over, modelID: "m1").percentText == "100%")
        #expect(ModelDownloadStatus(state: under, modelID: "m1") == .paused(progress: 0))
        #expect(ModelDownloadStatus(state: under, modelID: "m1").percentText == "0%")
    }

    @Test("未下载模型没有百分比文案")
    func nonProgressStatesHaveNoPercent() {
        #expect(ModelDownloadStatus.notDownloaded.percentText == nil)
        #expect(ModelDownloadStatus.downloaded.percentText == nil)
        #expect(ModelDownloadStatus.failed.percentText == nil)
        #expect(ModelDownloadStatus.unavailable.percentText == nil)
    }

    // MARK: - 选择器接入

    @Test("选择器订阅下载器，状态变化立即反映到模型列表")
    func viewModelTracksDownloaderState() {
        let provider = DownloadTestProvider(models: ["m1", "m2"])
        let viewModel = Self.makeViewModel(provider: provider)

        #expect(viewModel.downloadStatus(providerID: provider.providerID, model: "m1") == .downloaded)
        #expect(viewModel.downloadStatus(providerID: provider.providerID, model: "m2") == .notDownloaded)

        provider.send(LLMModelDownloadState(
            status: .downloading,
            modelID: "m2",
            progress: .init(fractionCompleted: 0.5),
            downloadedModelIDs: ["m1"]
        ))
        #expect(viewModel.downloadStatus(providerID: provider.providerID, model: "m2") == .downloading(progress: 0.5))

        provider.send(LLMModelDownloadState(
            status: .idle,
            downloadedModelIDs: ["m1", "m2"]
        ))
        #expect(viewModel.downloadStatus(providerID: provider.providerID, model: "m2") == .downloaded)
    }

    @Test("不支持下载的供应商不展示下载角标")
    func providerWithoutDownloadingHasNoBadge() {
        let provider = PlainTestProvider(models: ["m1"])
        let viewModel = Self.makeViewModel(provider: provider)

        #expect(viewModel.downloadStatus(providerID: provider.providerID, model: "m1") == .unavailable)
    }

    // MARK: - Helpers

    private static func makeViewModel(provider: ManagedLLMProvider) -> ModelSelectorViewModel {
        let manager = DefaultLLMManager()
        try? manager.register(provider)
        let box = LLMProviderManagerBox(manager: manager)
        let viewModel = ModelSelectorViewModel(
            box: box,
            usageStore: ProviderUsageStore(directory: nil),
            toastCapability: ModelSelectorToastCapabilityAdapter(toast: nil)
        )
        viewModel.selectedProviderID = provider.providerID
        return viewModel
    }
}

/// 同时具备下载能力的本地供应商替身。
@MainActor
private final class DownloadTestProvider: ManagedLLMProvider, LLMModelDownloadProviding {
    let providerInfo: LLMProviderInfo
    private let subject: CurrentValueSubject<LLMModelDownloadState, Never>

    init(models: [String]) {
        providerInfo = LLMProviderInfo(
            id: "download-provider",
            displayName: "Local",
            defaultModel: models[0],
            models: models.map { LLMModelInfo(id: $0) },
            isLocal: true
        )
        // 默认把首个模型视为已下载，便于区分「已下载/未下载」两条路径。
        subject = CurrentValueSubject(LLMModelDownloadState(
            status: .idle,
            downloadedModelIDs: [models[0]]
        ))
    }

    var providerID: String { providerInfo.id }

    func send(_ state: LLMModelDownloadState) {
        subject.send(state)
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        LLMResponse(content: "ok", model: request.model)
    }

    // MARK: LLMModelDownloadProviding

    var downloadState: LLMModelDownloadState { subject.value }
    var downloadStatePublisher: AnyPublisher<LLMModelDownloadState, Never> {
        subject.eraseToAnyPublisher()
    }
    var modelCacheDirectoryURL: URL { URL(fileURLWithPath: "/tmp/lumi-download-test", isDirectory: true) }

    func download(modelID: String) async {}
    func pauseDownload() {}
    func resumeDownload() async {}
    func cancelDownload() {}
    func deleteDownloadedModel(modelID: String) throws {}
    func setDownloadSpeedLimit(bytesPerSecond: Int?) {}
    func refreshDownloadState() {}
}

/// 普通远程供应商替身（未实现下载能力）。
@MainActor
private final class PlainTestProvider: ManagedLLMProvider {
    let providerInfo: LLMProviderInfo

    init(models: [String]) {
        providerInfo = LLMProviderInfo(
            id: "plain-provider",
            displayName: "Plain",
            defaultModel: models[0],
            models: models.map { LLMModelInfo(id: $0) }
        )
    }

    var providerID: String { providerInfo.id }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        LLMResponse(content: "ok", model: request.model)
    }
}