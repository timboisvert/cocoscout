import HotwireNative
import UIKit

/// A page's main form button, shown in the native nav bar. The web half
/// (bridge/form_controller.js) sends the button's title on connect; tapping
/// the native button asks the page to submit.
final class FormComponent: BridgeComponent {
    nonisolated override class var name: String { "form" }

    override func onReceive(message: Message) {
        switch message.event {
        case "connect":
            guard let data: MessageData = message.data() else { return }
            addButton(title: data.title)
        case "disconnect":
            removeButton()
        default:
            break
        }
    }

    private var viewController: UIViewController? {
        delegate?.destination as? UIViewController
    }

    private func addButton(title: String) {
        let action = UIAction { [weak self] _ in
            self?.reply(to: "connect")
        }
        let button = UIBarButtonItem(title: title, primaryAction: action)
        button.style = .done
        viewController?.navigationItem.rightBarButtonItem = button
    }

    private func removeButton() {
        viewController?.navigationItem.rightBarButtonItem = nil
    }
}

private struct MessageData: Decodable {
    let title: String
}
