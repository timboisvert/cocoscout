import HotwireNative
import UIKit
import WebKit

/// A page's Section row opens the phone's own menu (Tim, 2026-11-20), in
/// place of the page's slide-up sheet. The web half
/// (bridge/sections_controller.js) says where the row is on the page and
/// what the sections are; we lay a clear button over the row, inside the web
/// view's scroll view so it moves with the page, and its menu is the
/// sections under their headings. A pick goes back to the page, which opens
/// that section exactly as the sheet's row would.
final class SectionsComponent: BridgeComponent {
    nonisolated override class var name: String { "sections" }

    private var button: UIButton?

    override func onReceive(message: Message) {
        switch message.event {
        case "connect":
            guard let data: MessageData = message.data() else { return }
            place(data)
        case "disconnect":
            remove()
        default:
            break
        }
    }

    // The web view is shared between screens: the button never outlives ours.
    override func onViewWillDisappear() {
        button?.isHidden = true
    }

    override func onViewDidAppear() {
        button?.isHidden = false
    }

    private var scrollView: UIScrollView? {
        (delegate?.destination as? HotwireWebViewController)?.visitableView.webView?.scrollView
    }

    private func place(_ data: MessageData) {
        guard let scrollView, data.rect.width > 0, data.rect.height > 0 else { return remove() }

        let button = self.button ?? UIButton(type: .custom)
        if button.superview !== scrollView {
            button.removeFromSuperview()
            scrollView.addSubview(button)
        }
        // The page's own row shows through; ours only takes the tap.
        button.backgroundColor = .clear
        button.layer.cornerRadius = 8
        button.showsMenuAsPrimaryAction = true
        button.frame = CGRect(x: data.rect.x, y: data.rect.y, width: data.rect.width, height: data.rect.height)
        button.menu = menu(data.groups)
        button.accessibilityLabel = "Section: \(data.groups.flatMap(\.items).first(where: \.selected)?.title ?? "")"
        button.accessibilityHint = "Opens the list of sections"
        self.button = button
    }

    private func remove() {
        button?.removeFromSuperview()
        button = nil
    }

    private func menu(_ groups: [SectionGroup]) -> UIMenu {
        UIMenu(children: groups.map { group in
            UIMenu(title: group.title, options: .displayInline, children: group.items.map { item in
                UIAction(title: item.title,
                         image: item.locked ? UIImage(systemName: "lock") : nil,
                         attributes: item.danger ? .destructive : [],
                         state: item.selected ? .on : .off) { [weak self] _ in
                    guard let self else { return }
                    Task { _ = try? await self.reply(to: "connect", with: Pick(index: item.index)) }
                }
            })
        })
    }
}

private struct MessageData: Decodable {
    let rect: Rect
    let groups: [SectionGroup]
}

private struct Rect: Decodable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
}

private struct SectionGroup: Decodable {
    let title: String
    let items: [SectionItem]
}

private struct SectionItem: Decodable {
    let index: Int
    let title: String
    let selected: Bool
    let danger: Bool
    let locked: Bool
}

private struct Pick: Encodable {
    let index: Int
}
