import UIKit
import WebKit

/// The floating menu button: Coco's face in a white circle with a pink ring,
/// at the bottom right, opening the menu. It gets itself out of the page's
/// way (Tim, 2026-11-06): the page says what is pinned at its bottom
/// (MenuButtonComponent) and the button sits above it, or goes away while
/// the reader scrolls down or a sheet is over the page.
final class MenuButton: UIButton {
    private let onTap: () -> Void
    /// At rest: down where a tab bar would sit, a little into the
    /// home-indicator area.
    private static let restingOffset: CGFloat = 10
    /// The air between the button and a bar it sits above.
    private static let gap: CGFloat = 10
    private var bottomConstraint: NSLayoutConstraint?
    private var rise: CGFloat = 0
    private var away = false
    private weak var webView: WKWebView?
    private let circle = UIView()
    private let coco = UIImageView(image: UIImage(named: "LaunchLogo"))
    private let badgeLabel = UILabel()

    var badge: String? {
        didSet {
            badgeLabel.text = badge.map { " \($0) " }
            badgeLabel.isHidden = badge == nil
        }
    }

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
        super.init(frame: .zero)
        accessibilityLabel = "Menu"

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 4)

        // The circle clips Coco to head and collar; the badge sits outside it.
        circle.backgroundColor = .white
        circle.layer.cornerRadius = 30
        circle.layer.borderColor = AppConfig.pink.cgColor
        circle.layer.borderWidth = 3
        circle.clipsToBounds = true
        circle.isUserInteractionEnabled = false
        circle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(circle)

        coco.contentMode = .scaleAspectFit
        coco.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(coco)

        badgeLabel.font = .systemFont(ofSize: 12, weight: .bold)
        badgeLabel.textColor = .white
        // pink-600, as the website's counts (V1.1 plan §0a); V1.1 menus show none.
        badgeLabel.backgroundColor = UIColor(red: 0xE6 / 255, green: 0, blue: 0x76 / 255, alpha: 1)
        badgeLabel.layer.borderColor = UIColor.white.cgColor
        badgeLabel.layer.borderWidth = 2
        badgeLabel.layer.cornerRadius = 10
        badgeLabel.layer.masksToBounds = true
        badgeLabel.textAlignment = .center
        badgeLabel.isHidden = true
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            circle.topAnchor.constraint(equalTo: topAnchor),
            circle.bottomAnchor.constraint(equalTo: bottomAnchor),
            circle.leadingAnchor.constraint(equalTo: leadingAnchor),
            circle.trailingAnchor.constraint(equalTo: trailingAnchor),
            // A little wider than the circle and nudged down, so the face fills it.
            coco.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            coco.topAnchor.constraint(equalTo: circle.topAnchor, constant: 5),
            coco.widthAnchor.constraint(equalTo: circle.widthAnchor, multiplier: 1.1),
            coco.heightAnchor.constraint(equalTo: coco.widthAnchor, multiplier: 768.0 / 721.0),
            badgeLabel.topAnchor.constraint(equalTo: topAnchor, constant: -4),
            badgeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 4),
            badgeLabel.heightAnchor.constraint(equalToConstant: 20),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 20)
        ])

        addAction(UIAction { [weak self] _ in self?.onTap() }, for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use init(onTap:)")
    }

    override var isHighlighted: Bool {
        didSet { circle.alpha = isHighlighted ? 0.85 : 1 }
    }

    func install(in view: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(self)
        let bottom = bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: Self.restingOffset)
        bottomConstraint = bottom
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 60),
            heightAnchor.constraint(equalToConstant: 60),
            trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            bottom
        ])
    }

    // MARK: Getting out of the way

    /// rise: how far above the bottom of the page a bar pinned there reaches,
    /// in the page's points (0 with none). away: not there at all for now.
    /// webView: the page that said so, to find where its bottom is on screen.
    func place(rise newRise: CGFloat, away newAway: Bool, webView newWebView: WKWebView?, animated: Bool = true) {
        // With VoiceOver the button never leaves for a scroll: it has to stay findable.
        let goAway = newAway && !UIAccessibility.isVoiceOverRunning
        webView = newWebView
        guard newRise != rise || goAway != away else { return }
        rise = newRise
        away = goAway

        let changes = {
            self.bottomConstraint?.constant = self.bottomOffset()
            self.alpha = goAway ? 0 : 1
            self.transform = goAway && !UIAccessibility.isReduceMotionEnabled ? CGAffineTransform(scaleX: 0.5, y: 0.5) : .identity
            self.superview?.layoutIfNeeded()
        }
        accessibilityElementsHidden = goAway
        guard animated, window != nil else {
            changes()
            return
        }
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
    }

    /// The bottom edge, measured from the safe area's: the resting place, or
    /// higher when a pinned bar reaches above it.
    private func bottomOffset() -> CGFloat {
        guard rise > 0, let container = superview else { return Self.restingOffset }
        let safeBottom = container.bounds.maxY - container.safeAreaInsets.bottom
        // Where the page's own bottom is: pinned things sit on it.
        var pageBottom = container.bounds.maxY
        if let webView, webView.window != nil {
            pageBottom = webView.convert(webView.bounds, to: container).maxY - webView.scrollView.adjustedContentInset.bottom
        }
        let barTop = pageBottom - rise * (webView?.scrollView.zoomScale ?? 1)
        return min(Self.restingOffset, barTop - Self.gap - safeBottom)
    }

    /// Turning the phone moves the page's bottom and the safe area.
    override func layoutSubviews() {
        super.layoutSubviews()
        guard rise > 0, let constraint = bottomConstraint else { return }
        let offset = bottomOffset()
        if abs(constraint.constant - offset) > 0.5 { constraint.constant = offset }
    }
}
