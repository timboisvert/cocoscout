import Foundation

/// What a scan came to, as the door page shows it in its banner
/// (door_controller.js showBanner), sent over to show on the camera.
struct DoorResult: Decodable, Equatable {
    enum Tone: String, Decodable {
        case admitted
        case already
        case error
    }

    /// Something they pre-bought (a bottle) to hand over, with its Delivered
    /// address on the door page.
    struct Item: Decodable, Equatable, Identifiable {
        let id: Int
        let label: String
        let fulfilled: Bool
        let fulfillURL: String

        enum CodingKeys: String, CodingKey {
            case id, label, fulfilled
            case fulfillURL = "fulfill_url"
        }
    }

    let tone: Tone
    /// The first line is the big one: the name, or what went wrong.
    let lines: [String]
    /// Set on a fresh admit, which the door can take back for a couple of minutes.
    let undoTicketID: String?
    let items: [Item]
    /// The same result redrawn (an item just delivered): no sound or buzz.
    let quiet: Bool
    /// False when the door page's Sound switch is off on this phone: the
    /// buzz without the beep (Tim, 2026-11-27). Absent means on.
    let sound: Bool

    enum CodingKeys: String, CodingKey {
        case tone, lines, items, quiet, sound
        case undoTicketID = "undo_ticket_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tone = (try? container.decode(Tone.self, forKey: .tone)) ?? .error
        lines = (try container.decodeIfPresent([String?].self, forKey: .lines) ?? []).compactMap { $0 }
        undoTicketID = try container.decodeIfPresent(String.self, forKey: .undoTicketID)
        items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
        quiet = try container.decodeIfPresent(Bool.self, forKey: .quiet) ?? false
        sound = (try? container.decodeIfPresent(Bool.self, forKey: .sound)) ?? true
    }

    /// Something still to hand over keeps the result up until the next scan.
    var waitingOnDelivery: Bool {
        items.contains { !$0.fulfilled }
    }
}
