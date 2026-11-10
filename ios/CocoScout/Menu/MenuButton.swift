import UIKit

/// The menu button: Coco's face in a white circle with a pink ring, at the
/// right end of every page's top bar, after Messages and Notifications and
/// the size of their circles (WebViewController). It used to float over the
/// page's bottom right corner and was always over something (Tim, 2026-11-09).
final class MenuButton: UIButton {
    /// iOS 26 draws each bar icon in a 44pt glass circle; before it they are
    /// 40pt buttons.
    static let size: CGFloat = { if #available(iOS 26.0, *) { 44 } else { 40 } }()

    private static let nudge: CGFloat = { if #available(iOS 26.0, *) { 3 } else { 0 } }()

    private let circle = UIView()
    private let coco = UIImageView(image: UIImage(named: "LaunchLogo"))

    init(onTap: @escaping () -> Void) {
        super.init(frame: .zero)
        accessibilityLabel = "Menu"

        // The circle clips Coco to head and collar.
        circle.backgroundColor = .white
        circle.layer.cornerRadius = Self.size / 2
        circle.layer.borderColor = AppConfig.pink.cgColor
        circle.layer.borderWidth = 2
        circle.clipsToBounds = true
        circle.isUserInteractionEnabled = false
        circle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(circle)

        coco.contentMode = .scaleAspectFit
        coco.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(coco)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            // The bar sizes a custom view by its constraints, not its frame.
            widthAnchor.constraint(equalToConstant: Self.size),
            heightAnchor.constraint(equalToConstant: Self.size),
            circle.topAnchor.constraint(equalTo: topAnchor),
            circle.bottomAnchor.constraint(equalTo: bottomAnchor),
            // iOS 26 stands an item without its glass 3pt further from its
            // neighbor than the glass ones stand from each other; drawn 3pt
            // toward the bell, the three circles sit evenly.
            circle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -Self.nudge),
            circle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.nudge),
            // A little wider than the circle and nudged down, so the face fills it.
            coco.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            coco.topAnchor.constraint(equalTo: circle.topAnchor, constant: 4),
            coco.widthAnchor.constraint(equalTo: circle.widthAnchor, multiplier: 1.1),
            coco.heightAnchor.constraint(equalTo: coco.widthAnchor, multiplier: 768.0 / 721.0)
        ])

        addAction(UIAction { _ in onTap() }, for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use init(onTap:)")
    }

    override var isHighlighted: Bool {
        didSet { circle.alpha = isHighlighted ? 0.7 : 1 }
    }
}
