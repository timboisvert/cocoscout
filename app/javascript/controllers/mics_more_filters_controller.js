import { Controller } from "@hotwired/stimulus"

// Persists the open/closed state of the "More filters" accordion in
// localStorage so the user's choice survives navigation. If any of
// the included filters is active when the page loads, we auto-open
// regardless of stored state (so the user can see what's filtering).
export default class extends Controller {
  static targets = ["details"]
  static values = {
    storageKey:  String,
    defaultOpen: Boolean
  }

  connect() {
    const stored = this.read()
    const shouldOpen = this.defaultOpenValue || stored === true
    this.detailsTarget.open = shouldOpen
  }

  persist() {
    try {
      window.localStorage.setItem(this.storageKeyValue, this.detailsTarget.open ? "1" : "0")
    } catch (_e) {
      // Quota / private mode — no-op, persistence is best-effort.
    }
  }

  read() {
    try {
      const raw = window.localStorage.getItem(this.storageKeyValue)
      return raw === "1"
    } catch (_e) {
      return false
    }
  }
}
