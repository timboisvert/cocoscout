import HotwireNative
import UIKit

/// The door page's camera, done natively (bridge/door_scanner_controller.js).
///
/// - "connect" / "disconnect": the door page is open, so the phone stays
///   awake while it's on screen.
/// - "open": show the scanner. Every code it reads, and every Undo or
///   Delivered tap on a result, goes back as a reply to this message for the
///   page to act on; so does closing it.
/// - "result": what the page made of the last code, to show over the camera.
final class DoorScannerComponent: BridgeComponent {
    nonisolated override class var name: String { "door-scanner" }

    private var onDoorPage = false
    private weak var scanner: ScannerViewController?

    private var awakeKey: String { "door-page-\(ObjectIdentifier(self).hashValue)" }

    override func onReceive(message: Message) {
        switch message.event {
        case "connect":
            onDoorPage = true
            KeepAwake.hold(awakeKey)
        case "disconnect":
            onDoorPage = false
            KeepAwake.release(awakeKey)
        case "open":
            guard let data: OpenData = message.data() else { return }
            open(title: data.title, subtitle: data.subtitle)
        case "result":
            guard let result: DoorResult = message.data() else { return }
            scanner?.show(result)
        default:
            break
        }
    }

    override func onViewDidAppear() {
        if onDoorPage { KeepAwake.hold(awakeKey) }
    }

    override func onViewWillDisappear() {
        KeepAwake.release(awakeKey)
    }

    private func open(title: String, subtitle: String) {
        guard scanner == nil, let page = delegate?.destination as? UIViewController else { return }

        let scanner = ScannerViewController(title: title, subtitle: subtitle)
        scanner.onEvent = { [weak self] event in self?.send(event) }
        page.present(scanner, animated: true)
        self.scanner = scanner
    }

    private func send(_ event: ScannerViewController.Event) {
        let answer: Answer
        switch event {
        case .code(let code): answer = Answer(action: "code", value: code)
        case .undo(let ticketID): answer = Answer(action: "undo", value: ticketID)
        case .fulfill(let url): answer = Answer(action: "fulfill", value: url)
        case .closed: answer = Answer(action: "closed", value: nil)
        }
        reply(to: "open", with: answer)
    }
}

private struct OpenData: Decodable {
    let title: String
    let subtitle: String
}

private struct Answer: Encodable {
    let action: String
    let value: String?
}
