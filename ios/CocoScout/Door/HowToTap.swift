import ProximityReader
import UIKit

/// Apple's "How to Tap" guide for Tap to Pay on iPhone. Apple requires it
/// before someone takes their first tap; the tap page also offers it again
/// ("How to take a tap"). On iOS 18 and later it's Apple's own guide; on
/// iOS 17 (or if Apple's can't load), a short one of ours.
@MainActor
enum HowToTap {
    private static let shownKey = "TapToPay.howToTapShown"

    static var hasBeenShown: Bool {
        UserDefaults.standard.bool(forKey: shownKey)
    }

    /// Shows the guide over the page, returning once it's been dismissed.
    static func present(from page: UIViewController) async {
        UserDefaults.standard.set(true, forKey: shownKey)
        if #available(iOS 18.0, *) {
            do {
                let discovery = ProximityReaderDiscovery()
                let content = try await discovery.content(for: .payment(.howToTap))
                try await discovery.presentContent(content, from: topmost(page))
                return
            } catch {
                // Not available here (the Simulator, no network): ours instead.
            }
        }
        await presentOurs(from: topmost(page))
    }

    private static func presentOurs(from page: UIViewController) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let guide = UIAlertController(
                title: "How to take a tap",
                message: "When this iPhone asks for payment, have the buyer hold their contactless card, or their phone or watch with Apple Pay or Google Pay, flat against the top of this iPhone and keep it there until it checks. If their card asks for a PIN, they enter it on this screen.",
                preferredStyle: .alert
            )
            guide.addAction(UIAlertAction(title: "Got it", style: .default) { _ in done.resume() })
            page.present(guide, animated: true)
        }
    }

    /// Apple's guide has to be presented from the screen on top.
    private static func topmost(_ page: UIViewController) -> UIViewController {
        var top = page
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
