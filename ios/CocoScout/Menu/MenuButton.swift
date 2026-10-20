import UIKit

/// The floating menu button: Coco's face in a white circle with a pink ring,
/// always there at the bottom right, opening the full-screen menu. Shows the
/// total of every badge.
final class MenuButton: UIButton {
    private let onTap: () -> Void
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
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 60),
            heightAnchor.constraint(equalToConstant: 60),
            trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            // Down where a tab bar would sit, a little into the home-indicator area.
            bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: 10)
        ])
    }
}
