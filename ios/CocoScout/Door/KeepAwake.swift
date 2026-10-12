import UIKit

/// Keeps the screen from locking while anything asks it to: the door page
/// while it's showing, the scanner while it's open. The screen locks again
/// once the last one lets go.
@MainActor
enum KeepAwake {
    private static var holders = Set<String>()

    static func hold(_ holder: String) {
        holders.insert(holder)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    static func release(_ holder: String) {
        holders.remove(holder)
        UIApplication.shared.isIdleTimerDisabled = !holders.isEmpty
    }
}
