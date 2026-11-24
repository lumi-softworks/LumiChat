import Foundation
import ProviderMessageSender

/// 把编辑 Provider 的 `.began` / `.ended` 转给输入框 ViewModel。
@MainActor
final class EditSessionObserver {
    private weak var viewModel: ConversationInputViewModel?
    private var observer: (any MessageEditingObserverHandle)?

    init(
        capability: any ConversationInputCapability,
        viewModel: ConversationInputViewModel
    ) {
        self.viewModel = viewModel
        self.observer = capability.addEditingObserver { [weak viewModel] event in
            viewModel?.handleEditingEvent(event)
        }
    }

    func cancel() {
        observer?.cancel()
        observer = nil
        viewModel = nil
    }
}
