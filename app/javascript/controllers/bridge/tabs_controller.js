import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Bridge Component: the app's tab bar for the signed-in person, with badge
// counts, sent on every page load (shared/native/_bridge). An empty list means
// signed out, and the app shows just the sign-in screen.
export default class extends BridgeComponent {
  static component = "tabs"
  static values = { tabs: Array }

  connect() {
    super.connect()
    this.send("update", { tabs: this.tabsValue })
  }
}
