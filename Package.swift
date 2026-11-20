// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LumiChat",
    defaultLocalization: "en",
    platforms: [.macOS("14.0"), .iOS(.v17)],
    products: [
        .library(name: "PluginConversationInput", targets: ["PluginConversationInput"]),
        .library(name: "PluginConversationState", targets: ["PluginConversationState"]),
        .library(name: "PluginMessageListStandard", targets: ["PluginMessageListStandard"]),
        .library(name: "PluginMessageRenderer", targets: ["PluginMessageRenderer"]),
        .library(name: "PluginMessageSender", targets: ["PluginMessageSender"]),
        .library(name: "PluginModelSelector", targets: ["PluginModelSelector"]),
        .library(name: "PluginLLMProviderSettings", targets: ["PluginLLMProviderSettings"]),
        .library(name: "PluginLLMProviderOpenAI", targets: ["PluginLLMProviderOpenAI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/lumi-softworks/LumiProviders.git", from: "1.26.0"),
        .package(url: "https://github.com/lumi-softworks/LumiKernel.git", from: "1.1.1"),
        .package(url: "https://github.com/lumi-softworks/LumiUI.git", from: "1.18.1"),
        .package(url: "https://github.com/lumi-softworks/LumiLocalization.git", from: "1.0.2"),
        .package(url: "https://github.com/lumi-softworks/LumiLogging.git", from: "1.0.2"),
        .package(url: "https://github.com/lumi-softworks/LumiSettings.git", from: "1.1.1"),
        .package(url: "https://github.com/lumi-softworks/LumiKitLLM.git", from: "1.0.1"),
        .package(url: "https://github.com/lumi-softworks/LumiProviderToolManager.git", from: "1.0.2"),
        .package(url: "https://github.com/lumi-softworks/LumiKitMarkdown.git", from: "1.0.0"),
        .package(url: "https://github.com/lumi-softworks/LumiKitMessageList.git", from: "1.0.0"),
        .package(url: "https://github.com/lumi-softworks/LumiProviderAgentLoop.git", from: "1.0.0"),
        .package(url: "https://github.com/lumi-softworks/LumiProviderConversationInputBlock.git", from: "1.0.0"),
        .package(url: "https://github.com/lumi-softworks/LumiProviderConversationState.git", from: "1.0.0"),
        .package(url: "https://github.com/lumi-softworks/LumiProviderLifecycleHooks.git", from: "1.0.0"),
        .package(url: "https://github.com/lumi-softworks/LumiProviderLLMManager.git", from: "1.0.0"),
        .package(url: "https://github.com/lumi-softworks/LumiProviderMessage.git", from: "1.0.0"),
        .package(url: "https://github.com/lumi-softworks/LumiProviderMessageRendering.git", from: "1.0.0"),
        .package(url: "https://github.com/lumi-softworks/LumiProviderMessageSender.git", from: "1.0.0"),
        .package(url: "https://github.com/lumi-softworks/LumiProviderMessageStreaming.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "PluginConversationInput",
            dependencies: [
                .product(name: "KernelCore", package: "LumiKernel"),
                .product(name: "LumiLocalizationKit", package: "LumiLocalization"),
                .product(name: "LumiUI", package: "LumiUI"),
                .product(name: "ProviderChatSection", package: "LumiProviders"),
                .product(name: "ProviderConversationInputBlock", package: "LumiProviderConversationInputBlock"),
                .product(name: "ProviderConversation", package: "LumiProviders"),
                .product(name: "ProviderConversationState", package: "LumiProviderConversationState"),
                .product(name: "ProviderConversationInput", package: "LumiProviders"),
                .product(name: "ProviderMessage", package: "LumiProviderMessage"),
                .product(name: "ProviderMessageSender", package: "LumiProviderMessageSender"),
                .product(name: "LumiLoggingKit", package: "LumiLogging"),
            ],
            path: "Modules/PluginConversationInput/Sources/PluginConversationInput",
            resources: [.process("../../Resources/Localizable.xcstrings")]
        ),
        .target(
            name: "PluginConversationState",
            dependencies: [
                .product(name: "KernelCore", package: "LumiKernel"),
                .product(name: "ProviderAgentLoop", package: "LumiProviderAgentLoop"),
                .product(name: "ProviderConversation", package: "LumiProviders"),
                .product(name: "ProviderConversationState", package: "LumiProviderConversationState"),
                .product(name: "LumiLoggingKit", package: "LumiLogging"),
                .product(name: "ProviderToolManager", package: "LumiProviderToolManager"),
                .product(name: "ProviderMessageSender", package: "LumiProviderMessageSender"),
            ],
            path: "Modules/PluginConversationState/Sources/PluginConversationState"
        ),
        .target(
            name: "PluginMessageListStandard",
            dependencies: [
                .product(name: "KernelCore", package: "LumiKernel"),
                .product(name: "LumiUI", package: "LumiUI"),
                .product(name: "KitMarkdown", package: "LumiKitMarkdown"),
                .product(name: "KitMessageList", package: "LumiKitMessageList"),
                .product(name: "LumiLocalizationKit", package: "LumiLocalization"),
                .product(name: "ProviderAgentLoop", package: "LumiProviderAgentLoop"),
                .product(name: "ProviderChatSection", package: "LumiProviders"),
                .product(name: "ProviderConversation", package: "LumiProviders"),
                .product(name: "ProviderConversationState", package: "LumiProviderConversationState"),
                .product(name: "ProviderDeveloperMode", package: "LumiProviders"),
                .product(name: "ProviderLifecycleHooks", package: "LumiProviderLifecycleHooks"),
                .product(name: "ProviderMessage", package: "LumiProviderMessage"),
                .product(name: "ProviderMessageRendering", package: "LumiProviderMessageRendering"),
                .product(name: "ProviderMessageStreaming", package: "LumiProviderMessageStreaming"),
                .product(name: "ProviderPromptSuggestion", package: "LumiProviders"),
                .product(name: "ProviderProject", package: "LumiProviders"),
                .product(name: "ProviderToolbar", package: "LumiProviders"),
                .product(name: "ProviderToolManager", package: "LumiProviderToolManager"),
                .product(name: "LumiLoggingKit", package: "LumiLogging"),
            ],
            path: "Modules/PluginMessageListStandard/Sources/PluginMessageListStandard",
            resources: [.process("../../Resources/Localizable.xcstrings")]
        ),
        .target(
            name: "PluginMessageRenderer",
            dependencies: [
                .product(name: "KernelCore", package: "LumiKernel"),
                .product(name: "LumiLoggingKit", package: "LumiLogging"),
                .product(name: "ProviderConversation", package: "LumiProviders"),
                .product(name: "ProviderDeveloperMode", package: "LumiProviders"),
                .product(name: "ProviderAgentLoop", package: "LumiProviderAgentLoop"),
                .product(name: "ProviderChatSection", package: "LumiProviders"),
                .product(name: "ProviderMessage", package: "LumiProviderMessage"),
                .product(name: "ProviderMessageRendering", package: "LumiProviderMessageRendering"),
                .product(name: "ProviderMessageSender", package: "LumiProviderMessageSender"),
                .product(name: "ProviderToolManager", package: "LumiProviderToolManager"),
                .product(name: "LumiUI", package: "LumiUI"),
                .product(name: "LumiLocalizationKit", package: "LumiLocalization"),
                .product(name: "KitMarkdown", package: "LumiKitMarkdown"),
            ],
            path: "Modules/PluginMessageRenderer/Sources/PluginMessageRenderer",
            resources: [.process("../../Resources/Localizable.xcstrings")]
        ),
        .target(
            name: "PluginMessageSender",
            dependencies: [
                .product(name: "KernelCore", package: "LumiKernel"),
                .product(name: "ProviderMessageSender", package: "LumiProviderMessageSender"),
                .product(name: "ProviderAgentLoop", package: "LumiProviderAgentLoop"),
                .product(name: "ProviderConversation", package: "LumiProviders"),
                .product(name: "ProviderMessage", package: "LumiProviderMessage"),
                .product(name: "LumiLoggingKit", package: "LumiLogging"),
            ],
            path: "Modules/PluginMessageSender/Sources/PluginMessageSender"
        ),
        .target(
            name: "PluginModelSelector",
            dependencies: [
                .product(name: "KernelCore", package: "LumiKernel"),
                .product(name: "LumiLocalizationKit", package: "LumiLocalization"),
                .product(name: "LumiUI", package: "LumiUI"),
                .product(name: "ProviderChatSection", package: "LumiProviders"),
                .product(name: "ProviderConversation", package: "LumiProviders"),
                .product(name: "ProviderLLMManager", package: "LumiProviderLLMManager"),
                .product(name: "ProviderMessage", package: "LumiProviderMessage"),
                .product(name: "ProviderStorage", package: "LumiProviders"),
                .product(name: "KitLLM", package: "LumiKitLLM"),
                .product(name: "ProviderToast", package: "LumiProviders"),
            ],
            path: "Modules/PluginModelSelector/Sources/PluginModelSelector",
            resources: [.process("../../Resources/Localizable.xcstrings")]
        ),
        .target(
            name: "PluginLLMProviderSettings",
            dependencies: [
                .product(name: "KernelCore", package: "LumiKernel"),
                .product(name: "LumiLocalizationKit", package: "LumiLocalization"),
                .product(name: "LumiLoggingKit", package: "LumiLogging"),
                .product(name: "LumiUI", package: "LumiUI"),
                .product(name: "ProviderSettingView", package: "LumiSettings"),
                .product(name: "ProviderLLMManager", package: "LumiProviderLLMManager"),
                .product(name: "ProviderStorage", package: "LumiProviders"),
                .product(name: "KitLLM", package: "LumiKitLLM"),
            ],
            path: "Modules/PluginLLMProviderSettings/Sources/PluginLLMProviderSettings",
            resources: [.process("../../Resources/Localizable.xcstrings")]
        ),
        .target(
            name: "PluginLLMProviderOpenAI",
            dependencies: [
                .product(name: "KernelCore", package: "LumiKernel"),
                .product(name: "ProviderLLMManager", package: "LumiProviderLLMManager"),
                .product(name: "KitLLM", package: "LumiKitLLM"),
                .product(name: "LumiLoggingKit", package: "LumiLogging"),
            ],
            path: "Modules/PluginLLMProviderOpenAI/Sources/PluginLLMProviderOpenAI"
        ),
        .testTarget(
            name: "PluginConversationInputTests",
            dependencies: [
                "PluginConversationInput",
                .product(name: "ProviderAgentLoop", package: "LumiProviderAgentLoop"),
                .product(name: "ProviderConversation", package: "LumiProviders"),
                .product(name: "ProviderConversationInput", package: "LumiProviders"),
                .product(name: "ProviderConversationInputBlock", package: "LumiProviderConversationInputBlock"),
                .product(name: "ProviderLifecycleHooks", package: "LumiProviderLifecycleHooks"),
                .product(name: "ProviderMessage", package: "LumiProviderMessage"),
                .product(name: "ProviderMessageSender", package: "LumiProviderMessageSender"),
            ],
            path: "Modules/PluginConversationInput/Tests/PluginConversationInputTests"
        ),
        .testTarget(
            name: "PluginConversationStateTests",
            dependencies: [
                "PluginConversationState",
                .product(name: "ProviderConversation", package: "LumiProviders"),
            ],
            path: "Modules/PluginConversationState/Tests/PluginConversationStateTests"
        ),
        .testTarget(
            name: "PluginMessageListStandardTests",
            dependencies: [
                "PluginMessageListStandard",
                .product(name: "KitMessageList", package: "LumiKitMessageList"),
                .product(name: "ProviderAgentLoop", package: "LumiProviderAgentLoop"),
                .product(name: "ProviderMessage", package: "LumiProviderMessage"),
                .product(name: "ProviderConversation", package: "LumiProviders"),
                .product(name: "ProviderToolManager", package: "LumiProviderToolManager"),
                .product(name: "ProviderChatSection", package: "LumiProviders"),
                .product(name: "ProviderPromptSuggestion", package: "LumiProviders"),
                .product(name: "ProviderProject", package: "LumiProviders"),
                .product(name: "ProviderToolbar", package: "LumiProviders"),
                .product(name: "ProviderDeveloperMode", package: "LumiProviders"),
            ],
            path: "Modules/PluginMessageListStandard/Tests/PluginMessageListStandardTests"
        ),
        .testTarget(
            name: "PluginMessageRendererTests",
            dependencies: ["PluginMessageRenderer"],
            path: "Modules/PluginMessageRenderer/Tests/PluginMessageRendererTests"
        ),
        .testTarget(
            name: "PluginMessageSenderTests",
            dependencies: [
                "PluginMessageSender",
                .product(name: "KernelCore", package: "LumiKernel"),
                .product(name: "ProviderMessageSender", package: "LumiProviderMessageSender"),
                .product(name: "ProviderAgentLoop", package: "LumiProviderAgentLoop"),
                .product(name: "ProviderLifecycleHooks", package: "LumiProviderLifecycleHooks"),
                .product(name: "ProviderConversation", package: "LumiProviders"),
                .product(name: "ProviderMessage", package: "LumiProviderMessage"),
            ],
            path: "Modules/PluginMessageSender/Tests/PluginMessageSenderTests"
        ),
        .testTarget(
            name: "PluginModelSelectorTests",
            dependencies: [
                "PluginModelSelector",
                .product(name: "ProviderMessage", package: "LumiProviderMessage"),
            ],
            path: "Modules/PluginModelSelector/Tests/PluginModelSelectorTests"
        ),
        .testTarget(
            name: "PluginLLMProviderSettingsTests",
            dependencies: [
                "PluginLLMProviderSettings",
                .product(name: "KernelCore", package: "LumiKernel"),
                .product(name: "LumiLoggingKit", package: "LumiLogging"),
                .product(name: "ProviderLLMManager", package: "LumiProviderLLMManager"),
                .product(name: "ProviderStorage", package: "LumiProviders"),
                .product(name: "KitLLM", package: "LumiKitLLM"),
            ],
            path: "Modules/PluginLLMProviderSettings/Tests/PluginLLMProviderSettingsTests"
        ),
        .testTarget(
            name: "PluginLLMProviderOpenAITests",
            dependencies: [
                "PluginLLMProviderOpenAI",
                .product(name: "KernelCore", package: "LumiKernel"),
                .product(name: "ProviderLLMManager", package: "LumiProviderLLMManager"),
            ],
            path: "Modules/PluginLLMProviderOpenAI/Tests/PluginLLMProviderOpenAITests"
        ),
    ]
)
