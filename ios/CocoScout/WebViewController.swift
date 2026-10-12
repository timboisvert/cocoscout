import HotwireNative
import UIKit

/// Every web screen. The page's title sits on the left of the nav bar in
/// Coustard, next to the back button, instead of small and centered.
final class WebViewController: HotwireWebViewController {
    private let titleLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()

        titleLabel.font = AppConfig.coustard(22)
        titleLabel.textColor = .label
        titleLabel.lineBreakMode = .byTruncatingTail

        let item = UIBarButtonItem(customView: titleLabel)
        if #available(iOS 26.0, *) {
            item.hidesSharedBackground = true
        }
        navigationItem.leftItemsSupplementBackButton = true
        navigationItem.leftBarButtonItem = item
        // An empty title view keeps iOS from also centering the title.
        navigationItem.titleView = UIView()
    }

    /// Hotwire puts the page's <title> in navigationItem.title once it renders;
    /// show it in the left-hand label instead.
    override func visitableDidRender() {
        super.visitableDidRender()
        titleLabel.text = navigationItem.title
        let width = min(titleLabel.intrinsicContentSize.width, view.bounds.width - 120)
        titleLabel.frame = CGRect(x: 0, y: 0, width: width, height: 30)
    }
}
