import SwiftUI
import UIKit

/// The launch screen itself (LaunchScreen.storyboard: pink, the wordmark, the
/// tagline, and Coco rising from the bottom), for the app to draw. The sign-in
/// landing sits on it, and it covers the moment between launch and the sign-in
/// screen, so opening the app goes from the launch screen to the landing with
/// nothing in between (Tim, 2026-11-23, for 1.4.1). One storyboard lays out
/// both, so they line up on every screen size.
///
/// The storyboard's own view controller is embedded in a container: its view
/// takes the status bar's safe area from its controller, and the wordmark is
/// placed from that. The container sets that inset from the window itself the
/// moment it's laid out in one, since a safe area handed down the usual way
/// can arrive a frame late, and the wordmark would jump during iOS's fade
/// from the launch screen into the app. (A launch storyboard can't name a
/// class of the app's own, hence the container.)
enum LaunchBackdrop {
    static func makeController() -> UIViewController { Container() }

    /// Covers `parent` with the launch screen until the returned closure runs.
    static func cover(_ parent: UIViewController) -> () -> Void {
        let controller = makeController()
        parent.addChild(controller)
        controller.view.frame = parent.view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        parent.view.addSubview(controller.view)
        controller.didMove(toParent: parent)
        return {
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
        }
    }

    private final class Container: UIViewController {
        private let launch = UIStoryboard(name: "LaunchScreen", bundle: nil).instantiateInitialViewController() ?? UIViewController()

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = UIColor(named: "LaunchPink") ?? AppConfig.pink
            addChild(launch)
            launch.view.frame = view.bounds
            launch.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(launch.view)
            launch.didMove(toParent: self)
            // The storyboard's tags: 1 the wordmark, 2 the tagline, 3 Coco.
            if let title = view.viewWithTag(1) {
                title.isAccessibilityElement = true
                title.accessibilityLabel = "CocoScout"
                title.accessibilityTraits = .header
            }
            if let coco = view.viewWithTag(3) {
                coco.isAccessibilityElement = true
                coco.accessibilityLabel = "Coco, the CocoScout cat"
                coco.accessibilityTraits = .image
            }
        }

        override func viewWillLayoutSubviews() {
            super.viewWillLayoutSubviews()
            guard let window = view.window else { return }
            // What already reaches this view counts; only the rest is added.
            let top = max(0, window.safeAreaInsets.top - view.safeAreaInsets.top)
            if launch.additionalSafeAreaInsets.top != top {
                launch.additionalSafeAreaInsets = UIEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
            }
        }

        /// Every iPhone has a status bar inset; a frame laid out before it's
        /// known shows no wordmark rather than one in the wrong place.
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            let placed: CGFloat = launch.view.safeAreaInsets.top > 0 ? 1 : 0
            for tag in [1, 2] { view.viewWithTag(tag)?.alpha = placed }
        }
    }
}

/// The landing's background in SwiftUI. Without Coco when the landing draws
/// her itself, to move her behind the Welcome back card.
struct LaunchBackdropView: UIViewControllerRepresentable {
    var showsCoco = true

    func makeUIViewController(context: Context) -> UIViewController { LaunchBackdrop.makeController() }
    func updateUIViewController(_ controller: UIViewController, context: Context) {
        controller.view.viewWithTag(3)?.isHidden = !showsCoco
    }
}
