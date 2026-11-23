import { Controller } from "@hotwired/stimulus"
import { autofillSupported, requestOptions, credentialJSON, postJSON, getJSON } from "controllers/lib/webauthn"

// Passkeys in /signin's email field (SignIn::PasskeysController): a browser
// or password manager that holds a CocoScout passkey offers it in the
// field's autofill (autocomplete="username webauthn"), beside saved
// addresses. Choosing it signs in with Face ID, Touch ID, or a fingerprint,
// and lands where the email and password would have. Nothing shows in a
// browser without passkey autofill, and typing an address works as always.
export default class extends Controller {
  static targets = ["error"]
  static values = { optionsUrl: String, signInUrl: String }

  async connect() {
    if (!(await autofillSupported())) return
    this.abort = new AbortController()
    this.listen()
  }

  disconnect() {
    this.abort?.abort()
  }

  async listen() {
    const options = await getJSON(this.optionsUrlValue)
    if (!options || this.abort.signal.aborted) return

    let credential
    try {
      credential = await navigator.credentials.get({ publicKey: requestOptions(options), mediation: "conditional", signal: this.abort.signal })
    } catch {
      return // Left the page, or the browser closed its sheet.
    }
    if (!credential) return

    const answer = await postJSON(this.signInUrlValue, { credential: credentialJSON(credential) })
    if (answer.ok && answer.data.landing) {
      window.location.assign(answer.data.landing)
    } else {
      this.showError(answer.data.message || "That passkey didn't work. Try again, or continue with your email address.")
      this.listen() // Offer it again.
    }
  }

  showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("hidden")
  }
}
