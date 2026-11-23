import HotwireNative
import UIKit

/// Add a passkey on the Account page, in the app (bridge/passkey_controller.js):
/// iOS's own sheet makes it with Face ID and keeps it in iCloud Keychain
/// (PasskeyMaker, through App::PasskeysController), and the page reloads to
/// list it. Answers { status: "added" | "canceled" | "exists" | "failed", message }.
final class PasskeyComponent: BridgeComponent {
    nonisolated override class var name: String { "passkey" }

    override func onReceive(message: Message) {
        guard message.event == "add" else { return }
        Task { @MainActor in
            PasskeyMaker.shared.make { outcome in
                let answer: Answer = switch outcome {
                case .added(let name): Answer(status: "added", message: name)
                case .canceled: Answer(status: "canceled", message: nil)
                case .exists: Answer(status: "exists", message: "This iPhone already has a passkey for your account.")
                case .failed(let words): Answer(status: "failed", message: words)
                }
                Task { _ = try? await self.reply(to: "add", with: answer) }
            }
        }
    }

    private struct Answer: Encodable {
        let status: String
        let message: String?
    }
}
