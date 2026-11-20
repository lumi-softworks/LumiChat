# LumiChat

[English](README.md) | 中文

LumiChat 是 Lumi 体系应用共享的聊天功能层。它集中提供会话输入、消息列表、消息渲染、消息发送、会话状态、模型选择、供应商设置与 OpenAI 供应商，让不同宿主复用同一套聊天体验，而不是各自维护一份复制代码。

本包遵循 Lumi 的 **Kernel / Provider / Plugin** 架构：宿主负责应用装配与存储，插件之间通过 Provider 契约协作，不直接依赖其他业务插件。

## 功能特性

- 可复用的会话输入框，支持附件、发送与停止。
- 标准分页消息列表，流式回复独立更新。
- 可扩展的消息渲染，覆盖 Markdown、工具调用、授权、错误与回合活动。
- 共享的消息发送与会话活动状态。
- 通过聊天操作栏选择供应商和模型。
- 供应商设置界面，支持自定义云端供应商配置。
- 内置 OpenAI 供应商，可接入宿主提供的 HTTP 网络能力。
- 支持 macOS 与 iOS，包含本地化资源和模块测试。

## 产品清单

每个产品都是独立的 Swift 模块。宿主可以接入完整聊天栈，也可以只选择需要的产品。

| Product | 插件类型 | 职责 |
| --- | --- | --- |
| `PluginConversationInput` | `ConversationInputPlugin` | 输入框、附件、操作栏发送/停止按钮 |
| `PluginConversationState` | `ConversationStatePlugin` | 根据发送器、Agent Loop 和工具状态推导会话活动 |
| `PluginMessageListStandard` | `PluginMessageListStandardPlugin` | 标准消息列表、分页、滚动与流式尾行 |
| `PluginMessageRenderer` | `MessageRendererPlugin` | 消息、Markdown、工具调用、授权与错误渲染器 |
| `PluginMessageSender` | `MessageSenderPlugin` | `MessageSendingProviding`、待发送队列、首次发送时创建会话 |
| `PluginModelSelector` | `ModelSelectorPlugin` | 供应商/模型选择与切换反馈 |
| `PluginLLMProviderSettings` | `LLMProviderSettingsPlugin` | 供应商设置与自定义云端供应商存储 |
| `PluginLLMProviderOpenAI` | `OpenAIProviderPlugin` | 向 `LLMManaging` 注册 OpenAI |

各模块的详细文档保留在 [`Modules/`](Modules/) 下对应目录中。

## 架构

```text
宿主应用
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

设计约束：

- 插件依赖 `Provider*` 与 `Kit*` 契约，不依赖其他业务插件。
- 宿主在内核启动前注册基础 Provider，并决定最终插件装配顺序。
- 聊天 UI 通过 `ChatSectionProviding` 贡献，不要求宿主切换成独立的全屏聊天工作区。
- 会话与消息持久化始终位于宿主拥有的 Provider 之后。
- `LLMNetworkProviding` 是可选项；未提供时，供应商请求使用包内默认的 `URLSession` 网络实现。

## 环境要求

- Swift 6.0 工具链
- macOS 14 或更高版本
- iOS 17 或更高版本
- 使用 `KernelCore` 与相关 Provider 包的 Lumi 兼容宿主

## 当前依赖模式

> LumiChat 当前通过**本地 Swift Package 路径依赖**共享源码，尚不是可独立远程引用、带语义化版本的发布包。

根清单对共享基础设施使用 Lumi Softworks 远程包，同时对底层 Provider 与 Kit 源码使用 Lumi 仓库中的本地路径。这些路径要求如下相对目录结构：

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
            └── ... 其他相关 Provider 包
```

请确保兼容的 Lumi 检出的位置是 LumiChat 相对的 `../../Coffic/Lumi`。若要让 LumiChat 成为可独立消费的远程依赖，必须先发布或抽取这层底层依赖图。

## 接入方式

### 1. 添加本地包

根据宿主包的位置调整路径：

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

### 2. 注册宿主 Provider

启动这些插件前，宿主需要注册应用的基础 Provider。完整装配通常包括：

- `ChatSectionProviding`、`ConversationManaging`、`MessageManaging`
- `MessageStreamingProviding`、`MessageRenderingProviding`、`ToolCallRenderingProviding`
- `AgentLoopProviding`、`LLMManaging`、`ToolManagerProviding`
- `LifecycleHooksProviding`、`ConversationInputProviding`、`ConversationInputBlockProviding`
- 用于供应商设置与选择持久化的 `SettingViewProviding`、`StorageProviding`
- 用于完整标准列表体验的 `PromptSuggestionProviding`、`PromptSuggestionExecuting`、`ProjectProviding`、`ToolbarProviding`、`DeveloperModeProviding`
- 可选的 `LLMNetworkProviding`、`ToastProviding` 与 `RootViewProviding` 集成

实际所需子集取决于宿主选择的产品。Lode 的现有装配可作为参考：它先构建会话、消息、流式输出、生命周期、LLM、工具与 Agent Loop Provider，再创建这些插件。

### 3. 装配插件

以下顺序与 Lode 一致，可保持发送器、会话状态与输入框之间的接线：

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

将这些插件交给宿主其他插件共用的内核启动流程。

### 4. 挂载右侧聊天栏

LumiChat 提供聊天区内容，宿主决定聊天区出现在哪里。若需要 Lumi 风格的右侧栏，可将 `ChatSectionProviding` 挂到 `RootViewProviding`：

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

右栏何时显示、当前激活哪个工作区上下文，仍由宿主控制。

## OpenAI 与网络

`OpenAIProviderPlugin` 会向 `LLMManaging` 注册内置的 `openai` 供应商。用户通过供应商设置界面配置凭据与模型；本仓库不保存任何 API Key。

宿主注册 `LLMNetworkProviding` 后，OpenAI 与供应商设置请求会经过该桥接层，从而获得 HTTP 交换记录等宿主网络能力。未注册时会回退到默认的长空闲超时 `URLSession`；这是受支持的正式路径，不代表供应商注册失败。

## 示例：Lode 数据库 SQL 提案

Lode 将 LumiChat 与自身的 `PluginDatabaseManager` 工具组合：

1. 用户打开数据库工作区，在右侧聊天栏提出自然语言问题。
2. Lode 在每次 LLM 请求前注入当前连接、SQL 方言、数据库、schema 与查询标签页目标。
3. 模型可先检查真实 schema，再调用 Lode 的 `database_propose_sql` 工具。
4. 生成的 SQL 作为普通未保存编辑写入当前编辑器。
5. 用户审查 SQL，并显式点击现有 **Run** 按钮。

`database_propose_sql` 属于 Lode，不属于 LumiChat。它不会执行 SQL，也不会写入查询历史。Lode 原有执行与写操作确认流程仍是唯一权威路径；切换标签页、连接、数据库、schema 或修改编辑器后，过期提案会被拒绝。

这一分工体现了预期的包边界：LumiChat 提供共享聊天体验，宿主插件提供领域工具与执行策略。

## 仓库结构

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

每个模块包含自己的 `Sources/`、`Tests/`、资源、清单与 README；适用时还包含测试计划。根包聚合全部八个产品及其测试目标。

## 开发与测试

在所需 Lumi 检出就位后，从仓库根目录运行：

```sh
swift package dump-package
swift test
```

修改共享行为后，除了运行本包测试，还应运行受影响宿主的装配回归。包测试只能验证模块行为，不能替代宿主装配检查或真实 macOS/iOS UI 验证。

修改本地化文案时，请同步更新模块的 `Localizable.xcstrings` 与本地化测试。新增或重命名测试时，若模块维护 `Tests/TestPlan.md`，也必须同步更新。

## 范围与非目标

- LumiChat 不会再创建一套 Agent Loop、会话数据库或宿主根布局。
- 不包含 Lumi 的全工作区 `ChatPanelPlugin`；宿主可让原工作区与聊天右栏同时显示。
- 不包含无关的项目/RAG 空态行为。
- 不执行 SQL 查询等领域动作；领域工具与授权策略属于宿主。
- 在底层本地依赖完成抽取或发布前，不提供远程语义化版本接入。

## 贡献指南

请保持 Kernel / Provider / Plugin 边界，优先扩展 Provider 契约，而不是在业务插件之间增加依赖。行为变更应补回归测试，在适用时保持双平台兼容，并同步更新中英文文档。

欢迎提交 Issue 与 Pull Request。

## 使用 LumiChat 的项目

- [Lumi](https://github.com/CofficLab/Lumi) — 通过 `FactoryLumi` 与 `FactoryLumiACP` 使用完整共享聊天装配。
- [Lode](https://github.com/CofficLab/Lode) — 在数据库工作区接入共享右侧聊天栏与仅回填编辑器的 SQL 提案。
