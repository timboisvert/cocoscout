import { Controller } from "@hotwired/stimulus"

// Drives the "add a user by email" modals (producer roster, city captain,
// etc.). User types an email; we debounce + hit a per-context lookup
// endpoint. If a CocoScout user exists we show a "match" indicator and
// keep the name field hidden. If not, we reveal the name field (required)
// so a new account can be created and invited.
//
// Lookup endpoint contract — JSON with: { found, valid, email, name,
// already_on_mic }. `already_on_mic` is overloaded to mean "already
// attached at this scope" (mic roster, hub captains, etc.).
export default class extends Controller {
  static targets = ["email", "status", "newFields", "name", "submit"]
  static values  = { url: String, scopeLabel: { type: String, default: "this list" } }

  connect() {
    this._timer = null
    this._lastQuery = ""
    this.refresh()
  }

  // Triggered on input — debounced.
  search() {
    clearTimeout(this._timer)
    this._timer = setTimeout(() => this.fetchOnce(), 250)
  }

  async fetchOnce() {
    const email = this.emailTarget.value.trim().toLowerCase()
    if (email === this._lastQuery) return
    this._lastQuery = email

    if (!email) {
      this.setStatus("idle")
      return
    }

    // Crude client-side check to avoid noisy requests.
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      this.setStatus("invalid")
      return
    }

    this.setStatus("loading")
    try {
      const url = `${this.urlValue}?email=${encodeURIComponent(email)}`
      const res = await fetch(url, { headers: { Accept: "application/json" } })
      const data = await res.json()
      if (this.emailTarget.value.trim().toLowerCase() !== email) return // stale
      if (data.found) {
        if (data.already_on_mic) {
          this.setStatus("already", data)
        } else {
          this.setStatus("match", data)
        }
      } else {
        this.setStatus("new")
      }
    } catch (_e) {
      this.setStatus("idle")
    }
  }

  // Renders the status hint and toggles the name field.
  setStatus(kind, data = {}) {
    const s = this.statusTarget
    s.className = "mt-1 text-xs"
    switch (kind) {
      case "loading":
        s.textContent = "Looking up…"
        s.classList.add("text-gray-500")
        this.hideNewFields()
        this.enableSubmit(false)
        break
      case "invalid":
        s.textContent = ""
        this.hideNewFields()
        this.enableSubmit(false)
        break
      case "match":
        s.innerHTML = `<span class="text-emerald-700 font-bold">✓ Found on CocoScout${data.name ? `: ${this.escape(data.name)}` : ""}</span>`
        this.hideNewFields()
        this.enableSubmit(true)
        break
      case "already":
        s.innerHTML = `<span class="text-amber-700 font-bold">${this.escape(data.name || data.email)} is already on ${this.escape(this.scopeLabelValue)}.</span>`
        this.hideNewFields()
        this.enableSubmit(false)
        break
      case "new":
        s.innerHTML = `<span class="text-gray-700">No CocoScout account yet — we'll invite them.</span>`
        this.showNewFields()
        this.enableSubmit(true)
        break
      case "idle":
      default:
        s.textContent = ""
        this.hideNewFields()
        this.enableSubmit(false)
    }
  }

  showNewFields() {
    this.newFieldsTarget.classList.remove("hidden")
    if (this.hasNameTarget) this.nameTarget.required = true
  }

  hideNewFields() {
    this.newFieldsTarget.classList.add("hidden")
    if (this.hasNameTarget) this.nameTarget.required = false
  }

  enableSubmit(ok) {
    if (!this.hasSubmitTarget) return
    this.submitTarget.disabled = !ok
    this.submitTarget.classList.toggle("opacity-50", !ok)
    this.submitTarget.classList.toggle("cursor-not-allowed", !ok)
  }

  refresh() {
    this.enableSubmit(false)
  }

  escape(s) {
    const d = document.createElement("div")
    d.textContent = s
    return d.innerHTML
  }
}
