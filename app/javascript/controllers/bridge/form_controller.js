import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Bridge Component: shows a native submit button in the iOS nav bar on form pages.
// Activates automatically on any page that has a visible submit button.
export default class extends BridgeComponent {
  static component = "form"

  connect() {
    super.connect()
    const button = this.#findSubmitButton()
    if (!button) return

    const title = button.dataset.bridgeTitle
      || button.value
      || button.textContent.trim()
      || "Save"

    this.send("connect", { title }, () => {
      button.click()
    })
  }

  disconnect() {
    super.disconnect()
    this.send("disconnect")
  }

  #findSubmitButton() {
    return (
      document.querySelector("[data-bridge-title]") ||
      document.querySelector("form button[type='submit']") ||
      document.querySelector("form input[type='submit']") ||
      document.querySelector("button[type='submit']")
    )
  }
}
