import Foundation

/// The V1.1 menu the server sends generation-2 builds (NativeAppHelper#native_nav).
/// V1 builds never get it and keep drawing `[MenuItem]`.
struct NavData: Codable, Equatable {
    struct Section: Codable, Equatable {
        let label: String?
        let items: [NavItem]
    }

    struct NavItem: Codable, Equatable, Identifiable {
        let id: String
        let title: String
        let path: String
        let icon: String
        var badge: Int?
        var subtitle: String?
        var locked: Bool?
    }

    struct Icon: Codable, Equatable {
        let path: String
        let count: Int
    }

    struct Icons: Codable, Equatable {
        let messages: Icon
        let notifications: Icon
    }

    struct Organization: Codable, Equatable {
        let name: String
        let initials: String
        let sheetPath: String
    }

    struct ModeSwitch: Codable, Equatable {
        let label: String
        let subtitle: String
        let path: String
        let enter: Bool
    }

    let mode: String
    let sections: [Section]
    let icons: Icons
    let organization: Organization?
    let door: NavItem?
    let modeSwitch: ModeSwitch?
    let profilePath: String
    let settingsPath: String
    let signOutPath: String

    var isProduction: Bool { mode == "production" }
}

extension Notification.Name {
    /// Sent whenever a page brings a new V1.1 menu (the nav bar's icons follow it).
    static let cocoNavChanged = Notification.Name("CocoScout.navChanged")
}
