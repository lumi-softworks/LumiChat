import Foundation
import KitLLM
import ProviderConversation
import ProviderLLMManager
import ProviderMessage
import ProviderMessageSender
import Testing
@testable import PluginConversationInput

// MARK: - Fixtures

/// 固定内存刻度的判定夹具：16 GB 机器、8 GB 模型恰好压在 50% 线上。
private enum LocalModelWarningFixtures {
    static let gigabyte: Int64 = 1_024 * 1_024 * 1_024
    static let physicalMemory: Int64 = 16 * gigabyte

    static let heavyModel = LLMModelInfo(
        id: "heavy-local",
        displayName: "Heavy Local",
        minimumMemoryBytes: 8 * gigabyte
    )
    static let lightModel = LLMModelInfo(
        id: "light-local",
        displayName: "Light Local",
        minimumMemoryBytes: 1 * gigabyte
    )
    static let unknownMemoryModel = LLMModelInfo(id: "unknown-memory")
    static let zeroMemoryModel = LLMModelInfo(id: "zero-memory", minimumMemoryBytes: 0)

    static let localProvider = LLMProviderInfo(
        id: "mlx",
        displayName: "MLX",
        defaultModel: "heavy-local",
        models: [heavyModel, lightModel],
        isLocal: true
    )
    static let cloudProvider = LLMProviderInfo(
        id: "openai",
        displayName: "OpenAI",
        defaultModel: "gpt-x",
        models: [LLMModelInfo(id: "gpt-x", minimumMemoryBytes: 8 * gigabyte)],
        isLocal: false
    )

    static var heavyWarning: LocalModelMemoryWarning {
        LocalModelMemoryWarning(modelName: "Heavy Local", minimumMemoryBytes: 8 * gigabyte)
    }
}

// MARK: - 纯判定

@MainActor
@Suite("大内存本地模型纯判定")
struct LocalModelWarningDecisionTests {
    @Test("云模型不提醒：没有加载开销")
    func cloudModelNeverWarns() {
        let warning = LocalModelMemoryWarning.warningIfHeavy(
            providerInfo: LocalModelWarningFixtures.cloudProvider,
            modelInfo: LocalModelWarningFixtures.heavyModel,
            physicalMemoryBytes: LocalModelWarningFixtures.physicalMemory,
            isModelResident: nil
        )
        #expect(warning == nil)
    }

    @Test("内存需求未知或为零时不提醒")
    func unknownOrZeroMemoryNeverWarns() {
        for model in [LocalModelWarningFixtures.unknownMemoryModel, LocalModelWarningFixtures.zeroMemoryModel] {
            let warning = LocalModelMemoryWarning.warningIfHeavy(
                providerInfo: LocalModelWarningFixtures.localProvider,
                modelInfo: model,
                physicalMemoryBytes: LocalModelWarningFixtures.physicalMemory,
                isModelResident: nil
            )
            #expect(warning == nil)
        }
    }

    @Test("低于内存占比线的本地模型不提醒")
    func lightLocalModelDoesNotWarn() {
        let warning = LocalModelMemoryWarning.warningIfHeavy(
            providerInfo: LocalModelWarningFixtures.localProvider,
            modelInfo: LocalModelWarningFixtures.lightModel,
            physicalMemoryBytes: LocalModelWarningFixtures.physicalMemory,
            isModelResident: nil
        )
        #expect(warning == nil)
    }

    @Test("达到内存占比线的大本地模型提醒，并带出模型名与内存需求")
    func heavyLocalModelWarns() {
        let warning = LocalModelMemoryWarning.warningIfHeavy(
            providerInfo: LocalModelWarningFixtures.localProvider,
            modelInfo: LocalModelWarningFixtures.heavyModel,
            physicalMemoryBytes: LocalModelWarningFixtures.physicalMemory,
            isModelResident: nil
        )
        #expect(warning == LocalModelWarningFixtures.heavyWarning)
    }

    @Test("已驻留的模型不再提醒；未驻留与驻留未知均按保守策略提醒")
    func residencyDecidesWhetherToWarn() {
        func warning(isResident: Bool?) -> LocalModelMemoryWarning? {
            LocalModelMemoryWarning.warningIfHeavy(
                providerInfo: LocalModelWarningFixtures.localProvider,
                modelInfo: LocalModelWarningFixtures.heavyModel,
                physicalMemoryBytes: LocalModelWarningFixtures.physicalMemory,
                isModelResident: isResident
            )
        }
        #expect(warning(isResident: true) == nil)
        #expect(warning(isResident: false) == LocalModelWarningFixtures.heavyWarning)
        #expect(warning(isResident: nil) == LocalModelWarningFixtures.heavyWarning)
    }
}

// MARK: - 发送按钮门禁

@MainActor
@Suite("发送按钮大模型确认门禁")
struct SendActionBarLocalModelGateTests {
    private func makeGatedViewModel() -> (SendActionBarViewModel, SendActionBarTestCapability) {
        let capability = SendActionBarTestCapability()
        capability.text = "hello"
        capability.commit = MessageSendCommit(conversationID: UUID(), userMessageID: UUID())
        capability.localModelWarningResult = LocalModelWarningFixtures.heavyWarning
        let viewModel = SendActionBarViewModel(capability: capability)
        return (viewModel, capability)
    }

    @Test("有告警时发送不提交，草稿原样保留等待确认")
    func sendWithWarningDoesNotCommit() {
        let (viewModel, capability) = makeGatedViewModel()

        viewModel.send()

        #expect(capability.commits.isEmpty)
        #expect(capability.startedCommits.isEmpty)
        #expect(viewModel.pendingLocalModelWarning == LocalModelWarningFixtures.heavyWarning)
        #expect(capability.text == "hello")
    }

    @Test("确认后按快照提交并清空告警")
    func confirmCommitsAndClearsWarning() {
        let (viewModel, capability) = makeGatedViewModel()
        viewModel.send()

        viewModel.confirmLocalModelSend()

        #expect(capability.commits.count == 1)
        #expect(capability.commits.first?.content == "hello")
        #expect(viewModel.pendingLocalModelWarning == nil)
        // 提交成功，草稿按既有规则清空。
        #expect(capability.text.isEmpty)
    }

    @Test("确认期间修改文本，提交的仍是按下 Send 时的快照")
    func confirmCommitsSnapshotTakenAtSendPress() {
        let (viewModel, capability) = makeGatedViewModel()
        viewModel.send()

        capability.text = "edited while waiting"
        viewModel.confirmLocalModelSend()

        #expect(capability.commits.first?.content == "hello")
        // 新草稿不能被提交成功的清理误删（与 #1175 同一语义）。
        #expect(capability.text == "edited while waiting")
    }

    @Test("取消后不提交、告警清空、草稿原样保留")
    func cancelDiscardsPendingSend() {
        let (viewModel, capability) = makeGatedViewModel()
        viewModel.send()

        viewModel.cancelLocalModelSend()

        #expect(capability.commits.isEmpty)
        #expect(capability.startedCommits.isEmpty)
        #expect(viewModel.pendingLocalModelWarning == nil)
        #expect(capability.text == "hello")
    }

    @Test("无告警时发送直接提交，不进入待确认状态")
    func sendWithoutWarningCommitsDirectly() {
        let capability = SendActionBarTestCapability()
        capability.text = "hello"
        capability.commit = MessageSendCommit(conversationID: UUID(), userMessageID: UUID())
        capability.localModelWarningResult = nil
        let viewModel = SendActionBarViewModel(capability: capability)

        viewModel.send()

        #expect(capability.commits.count == 1)
        #expect(viewModel.pendingLocalModelWarning == nil)
    }
}

// MARK: - 输入框门禁

@MainActor
@Suite("输入框大模型确认门禁")
struct ConversationInputLocalModelGateTests {
    private func makeGatedViewModel() -> (ConversationInputViewModel, SendActionBarTestCapability) {
        let capability = SendActionBarTestCapability()
        capability.text = "hello"
        capability.commit = MessageSendCommit(conversationID: UUID(), userMessageID: UUID())
        capability.localModelWarningResult = LocalModelWarningFixtures.heavyWarning
        let viewModel = ConversationInputViewModel(capability: capability)
        return (viewModel, capability)
    }

    @Test("回车发送有告警时不提交，草稿原样保留等待确认")
    func sendWithWarningDoesNotCommit() {
        let (viewModel, capability) = makeGatedViewModel()

        viewModel.send()

        #expect(capability.commits.isEmpty)
        #expect(capability.startedCommits.isEmpty)
        #expect(viewModel.pendingLocalModelWarning == LocalModelWarningFixtures.heavyWarning)
        #expect(capability.text == "hello")
    }

    @Test("确认后按快照提交并清空告警")
    func confirmCommitsAndClearsWarning() {
        let (viewModel, capability) = makeGatedViewModel()
        viewModel.send()

        viewModel.confirmLocalModelSend()

        #expect(capability.commits.count == 1)
        #expect(capability.commits.first?.content == "hello")
        #expect(viewModel.pendingLocalModelWarning == nil)
        #expect(capability.text.isEmpty)
    }

    @Test("取消后不提交、告警清空、草稿原样保留")
    func cancelDiscardsPendingSend() {
        let (viewModel, capability) = makeGatedViewModel()
        viewModel.send()

        viewModel.cancelLocalModelSend()

        #expect(capability.commits.isEmpty)
        #expect(viewModel.pendingLocalModelWarning == nil)
        #expect(capability.text == "hello")
    }

    @Test("无告警时发送直接提交，不进入待确认状态")
    func sendWithoutWarningCommitsDirectly() {
        let capability = SendActionBarTestCapability()
        capability.text = "hello"
        capability.commit = MessageSendCommit(conversationID: UUID(), userMessageID: UUID())
        capability.localModelWarningResult = nil
        let viewModel = ConversationInputViewModel(capability: capability)

        viewModel.send()

        #expect(capability.commits.count == 1)
        #expect(viewModel.pendingLocalModelWarning == nil)
    }
}

// MARK: - 能力适配层

@MainActor
@Suite("输入能力大模型告警适配")
struct ConversationInputCapabilityWarningTests {
    /// 单个本地模型、可自报驻留状态的供应商替身。
    @MainActor
    private final class StubLocalProvider: SuperLLMProvider, LLMModelResidencyProviding {
        let providerID = "mlx"
        let providerInfo: LLMProviderInfo
        var isResident: Bool?

        init(modelInfo: LLMModelInfo) {
            providerInfo = LLMProviderInfo(
                id: "mlx",
                displayName: "MLX",
                defaultModel: modelInfo.id,
                models: [modelInfo],
                isLocal: true
            )
        }

        func complete(_ request: LLMRequest) async throws -> LLMResponse {
            LLMResponse(content: "ok", model: request.model)
        }

        func isModelResident(modelID: String) -> Bool? { isResident }
    }

    /// 不实现驻留查询的供应商替身：模拟未接入新契约的旧供应商。
    @MainActor
    private final class PlainLocalProvider: SuperLLMProvider {
        let providerID = "legacy"
        let providerInfo: LLMProviderInfo

        init(modelInfo: LLMModelInfo) {
            providerInfo = LLMProviderInfo(
                id: "legacy",
                displayName: "Legacy",
                defaultModel: modelInfo.id,
                models: [modelInfo],
                isLocal: true
            )
        }

        func complete(_ request: LLMRequest) async throws -> LLMResponse {
            LLMResponse(content: "ok", model: request.model)
        }
    }

    /// 固定注册单个供应商的最小 LLMManaging 替身。
    @MainActor
    private final class StubLLMManager: LLMManaging {
        let provider: any SuperLLMProvider

        var providerID: String { "test-manager" }
        var providerInfo = LLMProviderInfo(id: "test-manager", displayName: "Test Manager", defaultModel: "", models: [], isLocal: true)
        var selectedProviderID: String? { provider.providerID }
        var selectedModel: String? { provider.providerInfo.defaultModel }

        init(provider: any SuperLLMProvider) {
            self.provider = provider
        }

        func complete(_ request: LLMRequest) async throws -> LLMResponse {
            try await provider.complete(request)
        }
        func allProviders() -> [any SuperLLMProvider] { [provider] }
        func provider(id: String) -> (any SuperLLMProvider)? { provider.providerID == id ? provider : nil }
        var providerCount: Int { 1 }
        func register(_ provider: any SuperLLMProvider) throws {}
        func unregister(id: String) {}
        func models(for providerID: String) -> [String] { [provider.providerInfo.defaultModel] }
        func select(providerID: String, model: String?, reason: ModelSelectionReason) {}
    }

    /// 只覆盖模型选择相关成员的最小会话管理器替身。
    @MainActor
    private final class StubConversationManager: ConversationManaging {
        var selectedConversationID: UUID?
        /// 会话级模型原始 ID；`nil` 模拟未设置。
        var conversationModelID: String?

        func modelID(for conversationID: UUID?) -> String? { conversationModelID }

        // MARK: - 其余成员：与本用例无关，返回空值

        var dataDirectory: URL { URL(fileURLWithPath: "/tmp") }
        var conversations: [ConversationSummary] { [] }
        var currentTitle: String { "" }
        var globalVerbosity: ResponseVerbosity = .standard
        var globalReasoningEffort: ReasoningEffort?
        var globalAutomationLevel: AutomationLevel = .build
        var globalLanguage: ConversationLanguage = .chinese

        func createConversation(title: String?, projectPath: String?, providerID: String?, modelName: String?) throws -> UUID { UUID() }
        func createConversation(title: String?, projectPath: String?, providerID: String?, modelName: String?, parentConversationID: UUID?) throws -> UUID { UUID() }
        func selectConversation(id: UUID) {}
        func deselectConversation() {}
        func deleteConversation(id: UUID) {}
        func updateConversationTitle(_ title: String, for conversationID: UUID) -> Bool { false }
        func markConversationActive(id: UUID, messageDate: Date) {}
        func isSending(for conversationID: UUID?) -> Bool { false }
        func addSelectedConversationObserver(
            _ callback: @escaping (UUID?) -> Void
        ) -> any SelectedConversationObserverHandle {
            NoopSelectedConversationObserverHandle()
        }
        func selectProvider(id: String, model: String?, for conversationID: UUID?) {}
        func selectModel(id: String, for conversationID: UUID?) {}
        func setGlobalVerbosity(_ verbosity: ResponseVerbosity) {}
        func setVerbosity(_ verbosity: ResponseVerbosity, for conversationID: UUID?) {}
        func verbosity(for conversationID: UUID?) -> ResponseVerbosity { globalVerbosity }
        func setGlobalReasoningEffort(_ reasoningEffort: ReasoningEffort?) {}
        func reasoningEffort(for conversationID: UUID?) -> ReasoningEffort { .defaultEffort }
        func reasoningEffortOptional(for conversationID: UUID?) -> ReasoningEffort? { nil }
        func setReasoningEffort(_ reasoningEffort: ReasoningEffort, for conversationID: UUID?) {}
        func clearReasoningEffort(for conversationID: UUID?) {}
        func setGlobalAutomationLevel(_ automationLevel: AutomationLevel) {}
        func automationLevel(for conversationID: UUID?) -> AutomationLevel { globalAutomationLevel }
        func setAutomationLevel(_ automationLevel: AutomationLevel, for conversationID: UUID?) {}
        func setGlobalLanguage(_ language: ConversationLanguage) {}
        func language(for conversationID: UUID?) -> ConversationLanguage { globalLanguage }
        func setLanguage(_ language: ConversationLanguage, for conversationID: UUID?) {}
        func providerID(for conversationID: UUID?) -> String? { nil }
        func modelName(for conversationID: UUID?) -> String? { nil }
    }

    /// 取本机物理内存的 75%：任何机器上都超过 50% 告警线。
    private var heavyMemoryBytes: Int64 {
        Int64(ProcessInfo.processInfo.physicalMemory) * 3 / 4
    }

    private func makeAdapter(
        conversations: StubConversationManager,
        llmManager: StubLLMManager?
    ) -> ConversationInputCapabilityAdapter {
        ConversationInputCapabilityAdapter(
            input: nil,
            sender: nil,
            conversations: conversations,
            conversationState: nil,
            llmManager: llmManager
        )
    }

    @Test("会话级选中的大本地模型命中告警")
    func conversationLevelModelWarns() throws {
        let conversations = StubConversationManager()
        let conversationID = UUID()
        let provider = StubLocalProvider(modelInfo: LLMModelInfo(
            id: "heavy",
            displayName: "Heavy",
            minimumMemoryBytes: heavyMemoryBytes
        ))
        let manager = StubLLMManager(provider: provider)
        conversations.conversationModelID = LLMModelID(providerID: "mlx", modelID: "heavy")?.rawValue
        let adapter = makeAdapter(conversations: conversations, llmManager: manager)

        let warning = try #require(adapter.localModelMemoryWarning(for: conversationID))
        #expect(warning.modelName == "Heavy")
    }

    @Test("会话未设置模型时回退全局选中模型")
    func unsetConversationModelFallsBackToGlobalSelection() throws {
        let conversations = StubConversationManager()
        let provider = StubLocalProvider(modelInfo: LLMModelInfo(
            id: "heavy",
            displayName: "Heavy",
            minimumMemoryBytes: heavyMemoryBytes
        ))
        let manager = StubLLMManager(provider: provider)
        conversations.conversationModelID = nil
        let adapter = makeAdapter(conversations: conversations, llmManager: manager)

        let warning = try #require(adapter.localModelMemoryWarning(for: UUID()))
        #expect(warning.modelName == "Heavy")
    }

    @Test("会话级模型已失效时回退全局选中模型")
    func staleConversationModelFallsBackToGlobalSelection() throws {
        let conversations = StubConversationManager()
        let provider = StubLocalProvider(modelInfo: LLMModelInfo(
            id: "heavy",
            displayName: "Heavy",
            minimumMemoryBytes: heavyMemoryBytes
        ))
        let manager = StubLLMManager(provider: provider)
        // 指向不存在模型的原始 ID：解析不出路由，只能信全局选中。
        conversations.conversationModelID = LLMModelID(providerID: "mlx", modelID: "gone")?.rawValue
        let adapter = makeAdapter(conversations: conversations, llmManager: manager)

        let warning = try #require(adapter.localModelMemoryWarning(for: UUID()))
        #expect(warning.modelName == "Heavy")
    }

    @Test("供应商自报已驻留时不提醒，未驻留时提醒")
    func residencyFromProviderDecidesWarning() {
        let conversations = StubConversationManager()
        let provider = StubLocalProvider(modelInfo: LLMModelInfo(
            id: "heavy",
            displayName: "Heavy",
            minimumMemoryBytes: heavyMemoryBytes
        ))
        let manager = StubLLMManager(provider: provider)
        let adapter = makeAdapter(conversations: conversations, llmManager: manager)

        provider.isResident = true
        #expect(adapter.localModelMemoryWarning(for: nil) == nil)

        provider.isResident = false
        #expect(adapter.localModelMemoryWarning(for: nil) != nil)
    }

    @Test("供应商未接入驻留查询时按未知保守提醒")
    func providerWithoutResidencyWarnsConservatively() {
        let conversations = StubConversationManager()
        let provider = PlainLocalProvider(modelInfo: LLMModelInfo(
            id: "heavy",
            displayName: "Heavy",
            minimumMemoryBytes: heavyMemoryBytes
        ))
        let manager = StubLLMManager(provider: provider)
        let adapter = makeAdapter(conversations: conversations, llmManager: manager)

        #expect(adapter.localModelMemoryWarning(for: nil) != nil)
    }

    @Test("缺 LLM 管理能力时直接放行")
    func missingLLMManagerNeverWarns() {
        let conversations = StubConversationManager()
        let adapter = makeAdapter(conversations: conversations, llmManager: nil)

        #expect(adapter.localModelMemoryWarning(for: UUID()) == nil)
    }
}
