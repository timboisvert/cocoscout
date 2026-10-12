import UIKit

/// The one-button style's floating pink button: always there, bottom right,
/// opens the full-screen menu. Shows the total of every badge.
final class MenuButton: UIButton {
    private let onTap: () -> Void
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

        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = AppConfig.pink
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        configuration.image = UIImage(systemName: "square.grid.2x2.fill",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold))
        self.configuration = configuration
        accessibilityLabel = "Menu"

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 4)

        badgeLabel.font = .systemFont(ofSize: 12, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.backgroundColor = .systemRed
        badgeLabel.layer.cornerRadius = 10
        badgeLabel.layer.masksToBounds = true
        badgeLabel.textAlignment = .center
        badgeLabel.isHidden = true
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badgeLabel)
        NSLayoutConstraint.activate([
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
