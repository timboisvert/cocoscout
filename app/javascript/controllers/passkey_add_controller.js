import { Controller } from "@hotwired/stimulus"
import { passkeysSupported, creationOptions, credentialJSON, postJSON } from "controllers/lib/webauthn"

// Add a passkey, on the Account page in a browser (AccountPasskeysController):
// the options, the browser's own sheet (Touch ID, Windows Hello, a phone, a
// password manager), and the new passkey back to the server. The row stays
// hidden in a browser that can't make one.
export default class extends Controller {
  static targets = ["button", "error"]
  static values = { optionsUrl: String, createUrl: String }

  connect() {
    if (passkeysSupported()) this.element.classList.remove("hidden")
  }

  async add(event) {
    event.preventDefault()
    if (this.busy) return
    this.busy = true
    this.showError(null)
    try {
      const options = await postJSON(this.optionsUrlValue)
      if (!options.ok) return this.showError(options.data.message || "Passkeys can't be added right now. Please try again.")

      let credential
      try {
        credential = await navigator.credentials.create({ publicKey: creationOptions(options.data) })
      } catch (error) {
        // Closed the sheet: nothing to say. Already has one here: say so.
        if (error.name === "InvalidStateError") this.showError("This device or password manager already has a passkey for your account.")
        else if (error.name !== "NotAllowedError" && error.name !== "AbortError") this.showError("That passkey couldn't be added. Please try again.")
        return
      }
      if (!credential) return

      const saved = await postJSON(this.createUrlValue, { credential: credentialJSON(credential) })
      if (!saved.ok) return this.showError(saved.data.message || "That passkey couldn't be added. Please try again.")
      window.Turbo ? window.Turbo.visit(window.location.href, { action: "replace" }) : window.location.reload()
    } finally {
      this.busy = false
    }
  }

  showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message || ""
    this.errorTarget.classList.toggle("hidden", !message)
  }
}
