import { Controller } from "@hotwired/stimulus"

// The Notifications list: a row whose page lives in production mode asks
// first when the person is in My (unless they said not to), in a pink-header
// modal; "Don't ask again" remembers that on the server.
export default class extends Controller {
  static targets = ["modal", "organization", "remember"]
  static values = { ask: Boolean, rememberUrl: String }

  open(event) {
    const row = event.currentTarget
    if (!this.askValue || row.dataset.productionMode !== "true") return

    event.preventDefault()
    this.pendingUrl = row.href
    this.organizationTarget.textContent = row.dataset.organizationName || "your organization"
    this.rememberTarget.checked = false
    this.modalTarget.classList.remove("hidden")
  }

  async confirm() {
    if (this.rememberTarget.checked) {
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      await fetch(this.rememberUrlValue, { method: "POST", headers: { "X-CSRF-Token": token }, credentials: "same-origin" })
      this.askValue = false
    }
    const url = this.pendingUrl
    this.close()
    if (url) window.Turbo ? window.Turbo.visit(url) : (window.location.href = url)
  }

  close() {
    this.modalTarget.classList.add("hidden")
    this.pendingUrl = null
  }

  closeOnBackdrop(event) {
    if (event.target === this.modalTarget) this.close()
  }
}
