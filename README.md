# LumiChat

English | [中文](README_zh.md)

LumiChat is the shared chat feature layer for Lumi-based applications. It packages the conversation input, message list, rendering, sending, conversation state, model selection, provider settings, and OpenAI provider used by multiple hosts, so each application can present the same chat experience without maintaining a copied implementation.

The package follows the Lumi **Kernel / Provider / Plugin** architecture. Hosts own application composition and storage; plugins communicate through provider contracts rather than depending on one another.

## Features

- Reusable conversation composer with attachments, send, and stop behavior.
- Standard paginated message list with independent streaming output.
- Extensible message rendering for Markdown, tool calls, approvals, errors, and turn activity.
- Shared message-sending and conversation-activity state.
- Model and provider selection through the chat action bar.
- Provider settings, including custom cloud-provider configuration.
- Built-in OpenAI provider with optional host-provided HTTP networking.
- macOS and iOS package support with localized resources and module tests.

## Products

Each product is an independent Swift module. A host can adopt the complete chat stack or select only the products it needs.

| Product | Plugin type | Responsibility |
| --- | --- | --- |
| `PluginConversationInput` | `ConversationInputPlugin` | Composer, attachments, action-bar send/stop control |
| `PluginConversationState` | `ConversationStatePlugin` | Conversation activity derived from sender, agent loop, and tools |
| `PluginMessageListStandard` | `PluginMessageListStandardPlugin` | Standard message list, pagination, scrolling, and streaming row |
| `PluginMessageRenderer` | `MessageRendererPlugin` | Message, Markdown, tool-call, approval, and error renderers |
| `PluginMessageSender` | `MessageSenderPlugin` | `MessageSendingProviding`, pending queue, conversation creation on first send |
| `PluginModelSelector` | `ModelSelectorPlugin` | Provider/model selection and model-switch feedback |
| `PluginLLMProviderSettings` | `LLMProviderSettingsPlugin` | Provider settings and custom cloud-provider store |
| `PluginLLMProviderOpenAI` | `OpenAIProviderPlugin` | OpenAI registration with `LLMManaging` |

Module-specific documentation remains beside each module under [`Modules/`](Modules/).

## Architecture

```text
Host application
├── RootViewProviding / trailing pane
├── ChatSectionProviding
│   ├── ConversationInputPlugin
│   ├── PluginMessageListStandardPlugin
│   └── ModelSelectorPlugin
├── MessageSendingProviding
│   └── MessageSenderPlugin
├── ConversationStateProviding
│   └── ConversationStatePlugin
├── AgentLoopProviding
│   └── LLMManaging
│       └── OpenAIProviderPlugin
└── MessageManaging / MessageStreamingProviding
    └── MessageRenderingProviding
        └── MessageRendererPlugin
```

Design rules:

- Plugins depend on `Provider*` and `Kit*` contracts, not on other feature plugins.
- The host registers baseline providers before kernel startup and chooses the final plugin order.
- Chat UI is contributed through `ChatSectionProviding`; the package does not require a separate full-screen chat workspace.
- Conversation and message persistence remain behind host-owned providers.
- `LLMNetworkProviding` is optional. Without it, vendor requests use the package's default `URLSession` networking.

## Requirements

- Swift 6.0 toolchain
- macOS 14 or later
- iOS 17 or later
- A Lumi-compatible host using `KernelCore` and the related Provider packages

## Current dependency model

> LumiChat currently shares source through a **local Swift Package dependency**. It is not yet a self-contained remote package with a semantic-version release.

The root manifest uses remote Lumi Softworks packages for shared infrastructure, plus local paths for lower-level Provider and Kit sources in the Lumi repository. Those paths expect this relative checkout layout:

```text
<workspace>/
├── Lumi-Softworks/
│   └── LumiChat/
└── Coffic/
    └── Lumi/
        └── Packages/
            ├── KitMarkdown/
            ├── KitMessageList/
            ├── ProviderAgentLoop/
            ├── ProviderConversationState/
            ├── ProviderLLMManager/
            ├── ProviderMessage/
            └── ... related Provider packages
```

Keep a compatible Lumi checkout at `../../Coffic/Lumi` relative to LumiChat. Publishing LumiChat as an independently consumable remote dependency will require publishing or extracting that lower-level dependency graph first.

## Integration

### 1. Add the local package

Adjust the path for the host package location:

```swift
dependencies: [
    .package(path: "../Lumi-Softworks/LumiChat"),
],
targets: [
    .target(
        name: "MyHost",
        dependencies: [
            .product(name: "PluginConversationInput", package: "LumiChat"),
            .product(name: "PluginConversationState", package: "LumiChat"),
            .product(name: "PluginMessageListStandard", package: "LumiChat"),
            .product(name: "PluginMessageRenderer", package: "LumiChat"),
            .product(name: "PluginMessageSender", package: "LumiChat"),
            .product(name: "PluginModelSelector", package: "LumiChat"),
            .product(name: "PluginLLMProviderSettings", package: "LumiChat"),
            .product(name: "PluginLLMProviderOpenAI", package: "LumiChat"),
        ]
    ),
]
```

### 2. Register host providers

Register the application's baseline providers before booting these plugins. A complete assembly commonly includes:

- `ChatSectionProviding`, `ConversationManaging`, and `MessageManaging`
- `MessageStreamingProviding`, `MessageRenderingProviding`, and `ToolCallRenderingProviding`
- `AgentLoopProviding`, `LLMManaging`, and `ToolManagerProviding`
- `LifecycleHooksProviding`, `ConversationInputProviding`, and `ConversationInputBlockProviding`
- `SettingViewProviding` and `StorageProviding` for provider settings and persisted selection
- `PromptSuggestionProviding`, `PromptSuggestionExecuting`, `ProjectProviding`, `ToolbarProviding`, and `DeveloperModeProviding` for the full standard-list experience
- Optional `LLMNetworkProviding`, `ToastProviding`, and `RootViewProviding` integration

The exact subset depends on the products adopted by the host. Lode's working assembly is a useful reference: it constructs the conversation, message, streaming, lifecycle, LLM, tool, and agent-loop providers before creating the plugins.

### 3. Assemble the plugins

The following order is used by Lode and preserves the sender/state/input wiring:

```swift
import KernelCore
import PluginConversationInput
import PluginConversationState
import PluginLLMProviderOpenAI
import PluginLLMProviderSettings
import PluginMessageListStandard
import PluginMessageRenderer
import PluginMessageSender
import PluginModelSelector

@MainActor
func makeChatPlugins() -> [any SuperPlugin] {
    [
        MessageSenderPlugin(),
        ConversationStatePlugin(),
        MessageRendererPlugin(),
        OpenAIProviderPlugin(),
        PluginMessageListStandardPlugin(),
        ModelSelectorPlugin(),
        ConversationInputPlugin(),
        LLMProviderSettingsPlugin(),
    ]
}
```

Pass these plugins to the same kernel startup pipeline used by the rest of the host.

### 4. Mount the chat trailing pane

LumiChat supplies chat contributions, while the host decides where the chat section appears. For a Lumi-style right sidebar, mount `ChatSectionProviding` in `RootViewProviding`:

```swift
let trailingPane = RootTrailingPane(
    id: "com.coffic.lumi.workspace.chat",
    width: chat.chatSectionWidth,
    isVisible: chat.isVisible,
    content: chat.makeChatSectionView()
)
trailingPane.bindVisibility(to: chat)
trailingPane.bindWidth(to: chat) { chat.saveCurrentWidth($0) }
rootView.setTrailingPane(trailingPane)
chat.bindConversationSelection(conversations)
```

The host remains responsible for when the pane is visible and which workspace context is active.

## OpenAI and networking

`OpenAIProviderPlugin` registers the built-in `openai` provider with `LLMManaging`. Users configure credentials and models through the provider-settings UI; no API key is stored in this repository.

If the host registers `LLMNetworkProviding`, OpenAI and provider-settings requests use that bridge, allowing HTTP exchange recording or other host networking behavior. If it is absent, requests fall back to the default long-timeout `URLSession`; this fallback is supported and does not indicate a failed provider registration.

## Example: database SQL proposals in Lode

Lode combines LumiChat with its own `PluginDatabaseManager` tools:

1. The user opens a database workspace and asks a natural-language question in the trailing chat pane.
2. Lode injects the active connection, SQL dialect, database, schema, and query-tab target immediately before the LLM request.
3. The model can inspect the real schema and call Lode's `database_propose_sql` tool.
4. The generated SQL is inserted into the current editor as a normal unsaved edit.
5. The user reviews it and explicitly clicks the existing **Run** action.

`database_propose_sql` is owned by Lode, not LumiChat. It does not execute SQL or add query history. Lode's existing execution and write-confirmation paths remain authoritative, and stale proposals are rejected after tab, connection, database, schema, or editor changes.

This split demonstrates the intended package boundary: LumiChat supplies the shared conversation experience; host plugins supply domain tools and execution policy.

## Repository layout

```text
LumiChat/
├── Package.swift
├── Modules/
│   ├── PluginConversationInput/
│   ├── PluginConversationState/
│   ├── PluginMessageListStandard/
│   ├── PluginMessageRenderer/
│   ├── PluginMessageSender/
│   ├── PluginModelSelector/
│   ├── PluginLLMProviderSettings/
│   └── PluginLLMProviderOpenAI/
└── README.md
```

Each module contains its own `Sources/`, `Tests/`, resources, manifest, README, and test plan where applicable. The root package aggregates all eight products and their test targets.

## Development and tests

From the repository root, with the required Lumi checkout in place:

```sh
swift package dump-package
swift test
```

Run tests after changing shared behavior, and run the affected host compositions as well. A package test suite verifies module behavior; it does not replace host assembly checks or real macOS/iOS UI verification.

When changing localized text, update the module's `Localizable.xcstrings` catalog and its localization tests. When adding or renaming tests, keep the corresponding module `Tests/TestPlan.md` in sync where that module uses one.

## Scope and non-goals

- LumiChat does not create a second Agent loop, conversation database, or host root layout.
- It does not include Lumi's full-workspace `ChatPanelPlugin`; hosts can keep their existing workspace visible beside the chat pane.
- It does not include unrelated project/RAG empty-state behavior.
- It does not execute domain actions such as SQL queries. Domain tools and their authorization policies belong to the host.
- Remote semantic-version integration is deferred until the local lower-level dependencies are extracted or published.

## Contributing

Keep changes aligned with the Kernel / Provider / Plugin boundaries. Prefer extending a provider contract over adding a dependency between feature plugins. Add regression tests for behavior changes, preserve both platforms where applicable, and update English and Chinese documentation together.

Issues and pull requests are welcome.

## Projects using LumiChat

- [Lumi](https://github.com/CofficLab/Lumi) — full Lumi chat composition through `FactoryLumi` and `FactoryLumiACP`.
- [Lode](https://github.com/CofficLab/Lode) — database workspace with a shared trailing chat pane and editor-only SQL proposals.
