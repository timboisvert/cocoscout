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
    }

    /// Hotwire puts the page's <title> in navigationItem.title once it renders;
    /// show it in the left-hand label instead.
    override func visitableDidRender() {
        super.visitableDidRender()
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
