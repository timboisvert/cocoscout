import HotwireNative
import UIKit

/// Tap to Pay on the door phone (bridge/tap_to_pay_controller.js), on the
/// Stripe Terminal SDK.
///
/// - "pay": the door page holds seats for a sale. Connect to Terminal (a
///   token from connectionTokenUrl, with this sign-in's cookies), make the
///   PaymentIntent from the sale's amount and metadata, take the buyer's
///   tap, confirm it, and reply { status: "paid" | "failed" | "canceled",
///   message, paymentIntentId }. The page settles the order with the server
///   when it hears "paid". Before the first tap on this phone, Apple's How
///   to Tap guide comes first (HowToTap).
/// - "howToTap": the tap page's "How to take a tap" opens the guide again.
///
/// Built on stripe-terminal-ios 4.7 (the StripeTerminal package) and the
/// Tap to Pay entitlement in CocoScout.entitlements.
final class TapToPayComponent: BridgeComponent {
    nonisolated override class var name: String { "tap-to-pay" }

    /// The app's one reader, made on the first tap rather than with the
    /// page: starting Stripe Terminal asks for location, which only makes
    /// sense when taking a payment.
    private var reader: TapToPayReader { TapToPayReader.shared }

    override func onReceive(message: Message) {
        let page = delegate?.destination as? UIViewController
        if message.event == "howToTap" {
            guard let page else { return }
            Task { @MainActor in await HowToTap.present(from: page) }
            return
        }
        guard message.event == "pay", let data: TapToPayPayment = message.data() else { return }

        Task { @MainActor in
            if !HowToTap.hasBeenShown, let page {
                await HowToTap.present(from: page)
            }
            let outcome = await reader.take(data)
            _ = try? await reply(to: "pay", with: Answer(status: outcome.status, message: outcome.message,
                                                          paymentIntentId: outcome.paymentIntentId))
        }
    }
}

private struct Answer: Encodable {
    let status: String
    let message: String?
    let paymentIntentId: String?
}
