import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Bridge Component: the app's full-screen menu for the signed-in person, with
// badge counts, and who's signed in for the menu's pink card. Sent on every
// page load (shared/native/_bridge). An empty menu means signed out, and the
// app shows just the sign-in screen.
export default class extends BridgeComponent {
  static component = "menu"
  static values = { menu: Array, person: Object }

  connect() {
    super.connect()
    this.send("update", { menu: this.menuValue, person: this.hasPersonValue ? this.personValue : null })
  }
}
