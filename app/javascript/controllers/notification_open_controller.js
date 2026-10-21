import { Controller } from "@hotwired/stimulus"

// A list whose rows can open somewhere else: the Notifications list (a page
// in production mode, from My) and the one Messages inbox (a thread in
// production mode from My, or in another organization's). Such a row asks
// first in the pink-header prompt (shared/mode_switch_prompt), unless the
// person said not to; "Don't ask again" remembers that on the server. A row
// says so with data-switch="true" (data-production-mode="true" on the
// notifications list) and may bring its own title and body.
export default class extends Controller {
  static targets = ["modal", "organization", "remember", "title", "body"]
  static values = { ask: Boolean, rememberUrl: String }

  open(event) {
    const row = event.currentTarget
    if (!this.askValue || (row.dataset.switch !== "true" && row.dataset.productionMode !== "true")) return

    event.preventDefault()
    this.pendingUrl = row.href
    if (this.hasTitleTarget && row.dataset.switchTitle) this.titleTarget.textContent = row.dataset.switchTitle
    if (this.hasBodyTarget && row.dataset.switchBody) this.bodyTarget.textContent = row.dataset.switchBody
    else if (this.hasOrganizationTarget) this.organizationTarget.textContent = row.dataset.organizationName || "your organization"
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
