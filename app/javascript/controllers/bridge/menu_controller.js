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
  // nav: the V1.1 menu (NativeAppHelper#native_nav), only for generation-2
  // builds; V1 apps never get it and keep drawing `menu`.
  static values = { menu: Array, person: Object, tapToPay: Object, nav: Object }

  connect() {
    super.connect()
    const data = { menu: this.menuValue, person: this.hasPersonValue ? this.personValue : null,
                   tapToPay: this.hasTapToPayValue ? this.tapToPayValue : null }
    // Only when there is one: a V1 Android build's decoder may refuse a key
    // it doesn't know, so V1 phones get exactly the message they always did.
    if (this.hasNavValue) data.nav = this.navValue
    this.send("update", data)
  }
}
