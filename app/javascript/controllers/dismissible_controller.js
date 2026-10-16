import { Controller } from "@hotwired/stimulus"

// A box someone can close with its X, and that stays closed on this device
// for as long as its key holds (Ticketing home's Door open now: a key per
// organization and day, so the next show day brings it back). A convenience
// only: without storage it simply closes for this page.
export default class extends Controller {
  static values = { key: String }

  connect() {
    if (this.dismissed()) this.element.remove()
  }

  dismiss() {
    try { window.localStorage.setItem(this.storageKey, "1") } catch { /* fine without */ }
    this.element.remove()
  }

  dismissed() {
    try { return window.localStorage.getItem(this.storageKey) === "1" } catch { return false }
  }

  get storageKey() {
    return `cocoscout:dismissed:${this.keyValue}`
  }
}
