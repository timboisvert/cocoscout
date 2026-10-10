import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Bridge Component: puts a page's main form button in the app's nav bar.
// Only for pages that ask: mark the one button with data-bridge-title="Save"
// (or any label). Every other page leaves the nav bar alone.
export default class extends BridgeComponent {
  static component = "form"

  connect() {
    super.connect()
    const button = document.querySelector("[data-bridge-title]")
    if (!button) return

    this.send("connect", { title: button.dataset.bridgeTitle }, () => {
      button.click()
    })
  }

  disconnect() {
    super.disconnect()
    this.send("disconnect")
  }
}
