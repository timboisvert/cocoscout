import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Bridge Component: Add a passkey on the Account page, in the app
// (Bridge/PasskeyComponent.swift, bridge/PasskeyComponent.kt). The app's own
// sheet makes it (Face ID, a fingerprint) through App::PasskeysController,
// then the page reloads to list it. The server draws the row only for builds
// that list "passkey" in their user agent (account/show.html.erb), so there's
// never a button that does nothing.
export default class extends BridgeComponent {
  static component = "passkey"
  static targets = ["button", "error"]

  add(event) {
    event.preventDefault()
    if (!this.enabled) return

    this.showError(null)
    this.send("add", {}, (message) => {
      // { status: "added" | "canceled" | "exists" | "failed", message }
      const { status, message: words } = message.data
      if (status === "added") window.Turbo ? window.Turbo.visit(window.location.href, { action: "replace" }) : window.location.reload()
      else if (status !== "canceled") this.showError(words || "That passkey couldn't be added. Please try again.")
    })
  }

  showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message || ""
    this.errorTarget.classList.toggle("hidden", !message)
  }
}
