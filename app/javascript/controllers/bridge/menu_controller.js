import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Bridge Component: the app's full-screen menu for the signed-in person, with
// badge counts, and who's signed in for the menu's pink card. Sent on every
// page load (shared/native/_bridge). An empty menu means signed out, and the
// app shows just the sign-in screen.
export default class extends BridgeComponent {
  static component = "menu"
  // tapToPay: Tap to Pay on iPhone for someone who can sell with it
  // (NativeAppHelper#native_tap_to_pay), so the app can show Apple's
  // one-time screen and warm Terminal up; absent for everyone else.
  static values = { menu: Array, person: Object, tapToPay: Object }

  connect() {
    super.connect()
    this.send("update", { menu: this.menuValue, person: this.hasPersonValue ? this.personValue : null,
                          tapToPay: this.hasTapToPayValue ? this.tapToPayValue : null })
  }
}
