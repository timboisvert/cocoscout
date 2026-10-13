import HotwireNative
import UIKit

/// Tap to Pay on the door phone (bridge/tap_to_pay_controller.js), on the
/// Stripe Terminal SDK.
///
/// - "pay": the door page has a PaymentIntent for the sale. Connect to
///   Terminal (a token from connectionTokenUrl, with this sign-in's cookies),
///   take the buyer's tap for clientSecret, confirm it, and reply
///   { status: "paid" | "failed" | "canceled", message }. The page settles
///   the order with the server when it hears "paid".
///
/// Needs, on a Mac: the stripe-terminal-ios package (StripeTerminal), the
/// Tap to Pay entitlement in CocoScout.entitlements (added), and Apple's
/// "How to Tap" screen shown once before the first tap
/// (`Terminal.shared.supportsReaders` / the SDK's tap-to-pay education). The
/// SDK calls below follow Stripe Terminal iOS 4.x; check the names against
/// the version the package resolves to.
final class TapToPayComponent: BridgeComponent {
    nonisolated override class var name: String { "tap-to-pay" }

    private let reader = TapToPayReader()

    override func onReceive(message: Message) {
        guard message.event == "pay", let data: TapToPayPayment = message.data() else { return }

        Task { @MainActor in
            let outcome = await reader.take(data)
            reply(to: "pay", with: Answer(status: outcome.status, message: outcome.message))
        }
    }
}

private struct Answer: Encodable {
    let status: String
    let message: String?
}
