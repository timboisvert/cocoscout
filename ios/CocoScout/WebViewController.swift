import HotwireNative
import UIKit
import WebKit

/// Every web screen. The page's title sits on the left of the nav bar in
/// Coustard, next to the back button, instead of small and centered. On the
/// right: Messages, Notifications, then Coco (the menu) in a circle the size
/// of theirs (Tim, 2026-11-09).
final class WebViewController: HotwireWebViewController {
    private let titleLabel = UILabel()
    // iOS sizes a bar item to its view's full text unless told otherwise; a
    // title wider than the bar then hides behind the "more" button.
    private lazy var titleWidth = titleLabel.widthAnchor.constraint(equalToConstant: 0)
    private lazy var menuItem: UIBarButtonItem = {
        let item = UIBarButtonItem(customView: MenuButton { AppShell.shared.showMenu() })
        // Coco's own white circle and pink ring, not iOS 26's glass around it.
        if #available(iOS 26.0, *) {
            item.hidesSharedBackground = true
        }
        return item
    }()
    private var shownNav: NavData?

    override func viewDidLoad() {
        super.viewDidLoad()

        // 18, down from 22: it makes up the room Coco takes beside it.
        titleLabel.font = AppConfig.coustard(18)
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

    /// A page in a sheet over the screen (the organization menu, a form):
    /// it closes with Done and is about one thing, so its bar carries no
    /// Messages, Notifications or Coco (Tim, 2026-11-09). They are on the
    /// page under it.
    private var inSheet: Bool {
        navigationController?.presentingViewController != nil
    }

    /// Coco opens the menu from every page of someone signed in.
    private var showsMenuButton: Bool {
        AppShell.shared.signedIn && !inSheet
    }

    @objc private func navChanged(_ note: Notification) {
        showIcons(note.object as? NavData)
    }

    /// The right of the bar, from its edge inward: Coco, Notifications,
    /// Messages. The two icons carry their counts and open their pages on
    /// top. A gap between each gives it room to tap (and on iOS 26, its own
    /// glass button).
    private func showIcons(_ nav: NavData?) {
        shownNav = nav
        var items: [UIBarButtonItem] = showsMenuButton ? [menuItem] : []
        if let nav, !inSheet {
            // No spacer after Coco: an item drawn without iOS 26's glass
            // already stands a little apart, and the three sit evenly.
            if #unavailable(iOS 26.0), !items.isEmpty { items.append(.fixedSpace(10)) }
            items += [
                iconItem(systemName: "bell", label: "Notifications", icon: nav.icons.notifications),
                .fixedSpace(10),
                iconItem(systemName: "envelope", label: "Messages", icon: nav.icons.messages)
            ]
        }
        navigationItem.rightBarButtonItems = items.isEmpty ? nil : items
    }

    /// The icons come and go with signing in, and with being shown in a sheet.
    private func showMenuButton() {
        showIcons(shownNav)
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
    /// link to the welcome screen). Nor above the organization sheet: it
    /// opens on the organization's own name and logo, and a bar that only
    /// said "Organization" was wasted room (Tim, 2026-11-09). It closes by
    /// pulling down or tapping outside.
    private static let barlessPaths: Set<String> = ["/welcome", "/signin", "/signup", "/select/organization/menu"]

    private var hidesBar: Bool {
        Self.barlessPaths.contains(currentVisitableURL.path)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        showMenuButton()
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
        showMenuButton()
        titleLabel.text = navigationItem.title
        // Narrower beside a back button, and for Coco on the right. The title
        // is cut with "…" before the bar runs out of room: past that, iOS 26
        // folds the icons on the right into its "more" button (measured on a
        // 402pt-wide iPhone).
        let hasBackButton = navigationController?.viewControllers.first !== self
        let taken: CGFloat = (hasBackButton ? 225 : 120) + (showsMenuButton ? MenuButton.size + 10 : 0)
        let width = min(titleLabel.intrinsicContentSize.width, view.bounds.width - taken)
        titleWidth.constant = ceil(width)
    }
}
