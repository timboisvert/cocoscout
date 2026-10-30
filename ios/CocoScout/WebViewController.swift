import HotwireNative
import UIKit
import WebKit

/// Every web screen. The page's title sits on the left of the nav bar in
/// Coustard, next to the back button, instead of small and centered.
final class WebViewController: HotwireWebViewController {
    private let titleLabel = UILabel()
    // iOS sizes a bar item to its view's full text unless told otherwise; a
    // title wider than the bar then hides behind the "more" button.
    private lazy var titleWidth = titleLabel.widthAnchor.constraint(equalToConstant: 0)

    override func viewDidLoad() {
        super.viewDidLoad()

        titleLabel.font = AppConfig.coustard(22)
        titleLabel.textColor = .label
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([titleWidth, titleLabel.heightAnchor.constraint(equalToConstant: 30)])

        let item = UIBarButtonItem(customView: titleLabel)
        if #available(iOS 26.0, *) {
            item.hidesSharedBackground = true
        }
        navigationItem.leftItemsSupplementBackButton = true
        navigationItem.leftBarButtonItem = item
        // An empty title view keeps iOS from also centering the title.
        navigationItem.titleView = UIView()

        // V1.1: Messages and Notifications, on the right of every bar.
        NotificationCenter.default.addObserver(self, selector: #selector(navChanged), name: .cocoNavChanged, object: nil)
        showIcons(AppShell.shared.nav)
    }

    @objc private func navChanged(_ note: Notification) {
        showIcons(note.object as? NavData)
    }

    /// The two universal icons, with their counts, opening their pages on top.
    /// A gap between them gives each room to tap (and on iOS 26, its own
    /// glass button).
    private func showIcons(_ nav: NavData?) {
        guard let nav else {
            navigationItem.rightBarButtonItems = nil
            return
        }
        navigationItem.rightBarButtonItems = [
            iconItem(systemName: "bell", label: "Notifications", icon: nav.icons.notifications),
            .fixedSpace(10),
            iconItem(systemName: "envelope", label: "Messages", icon: nav.icons.messages)
        ]
    }

    private static let badgePink = UIColor(red: 0xE6 / 255, green: 0, blue: 0x76 / 255, alpha: 1)

    private func iconItem(systemName: String, label: String, icon: NavData.Icon) -> UIBarButtonItem {
        let image = UIImage(systemName: systemName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
        let accessibilityLabel = icon.count > 0 ? "\(label), \(icon.count) unread" : label
        let path = icon.path
        let action = UIAction { _ in AppShell.shared.open(path: path) }

        // iOS 26's glass bar doesn't draw a label added to a custom view, so
        // use a plain image item and Apple's own badge. The items are rebuilt
        // on every nav change, so the badge is set as each one is made.
        if #available(iOS 26.0, *) {
            let item = UIBarButtonItem(image: image, primaryAction: action)
            item.tintColor = AppConfig.pink
            item.accessibilityLabel = accessibilityLabel
            if let text = AppShell.badgeText(icon.count) {
                var badge = UIBarButtonItem.Badge.string(text)
                badge.backgroundColor = Self.badgePink
                badge.foregroundColor = .white
                item.badge = badge
            }
            return item
        }

        // iOS 17 and 18: the bar sizes a custom view by its constraints, not
        // its frame, so pin it to 40×40 and keep the count inside it.
        let button = UIButton(type: .system, primaryAction: action)
        button.setImage(image, for: .normal)
        button.tintColor = AppConfig.pink
        button.accessibilityLabel = accessibilityLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40)
        ])
        if let text = AppShell.badgeText(icon.count) {
            let badge = UILabel()
            badge.text = " \(text) "
            badge.font = .systemFont(ofSize: 10, weight: .bold)
            badge.textColor = .white
            badge.backgroundColor = Self.badgePink
            badge.textAlignment = .center
            badge.layer.cornerRadius = 8
            badge.layer.masksToBounds = true
            badge.layer.borderColor = UIColor.white.cgColor
            badge.layer.borderWidth = 1.5
            badge.isUserInteractionEnabled = false
            badge.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.topAnchor.constraint(equalTo: button.topAnchor, constant: 2),
                badge.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                badge.heightAnchor.constraint(equalToConstant: 16),
                badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 16)
            ])
        }
        return UIBarButtonItem(customView: button)
    }

    /// The welcome screen, sign-in and sign-up stand on their own: no bar
    /// above them (each has its own heading; sign-in and sign-up have a Back
    /// link to the welcome screen).
    private static let barlessPaths: Set<String> = ["/welcome", "/signin", "/signup"]

    private var hidesBar: Bool {
        Self.barlessPaths.contains(currentVisitableURL.path)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(hidesBar, animated: animated)
    }

    /// Hotwire puts the page's <title> in navigationItem.title once it renders;
    /// show it in the left-hand label instead.
    override func visitableDidRender() {
        super.visitableDidRender()
        // A page can turn out to be sign-in after a redirect (/my, signed out).
        if navigationController?.topViewController === self {
            navigationController?.setNavigationBarHidden(hidesBar, animated: false)
        }
        // App pages never zoom (their viewport says so). The app keeps one web
        // view for every page, so undo any zoom left over from before.
        if let scrollView = visitableView.webView?.scrollView, scrollView.zoomScale != 1 {
            scrollView.setZoomScale(1, animated: false)
            scrollView.contentOffset.x = 0
        }
        titleLabel.text = navigationItem.title
        // Narrower beside a back button: a title too wide for the bar gets
        // tucked into iOS's "more" menu instead of truncating.
        let hasBackButton = navigationController?.viewControllers.first !== self
        let width = min(titleLabel.intrinsicContentSize.width, view.bounds.width - (hasBackButton ? 180 : 120))
        titleWidth.constant = ceil(width)
    }
}
