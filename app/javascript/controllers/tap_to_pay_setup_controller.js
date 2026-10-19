import { Controller } from "@hotwired/stimulus"

// Tap to Pay on iPhone's page (door/tap_to_pay): shows how this iPhone
// stands, from the app's answers (tap-to-pay:state, from bridge--tap-to-pay),
// one panel at a time: not set up (with Set up), getting ready (with its
// progress, Apple 3.9.1), ready, or why it can't (an administrator has to
// accept Apple's terms first, Apple 3.8.1; or what went wrong). In a browser
// the app never answers and the page says to open it in the app.
export default class extends Controller {
  static targets = ["browser", "checking", "notSetUp", "preparing", "progress", "progressText", "ready", "needsAdmin", "failed", "failedText"]

  connect() {
    this.answered = false
    this.ask = setTimeout(() => this.askApp(), 50)
    this.fallback = setTimeout(() => { if (!this.answered) this.show("browser") }, 1500)
  }

  disconnect() {
    clearTimeout(this.ask)
    clearTimeout(this.fallback)
  }

  askApp() {
    this.dispatch("status")
  }

  // tap-to-pay:state — { state, progress, message }
  state({ detail }) {
    this.answered = true
    clearTimeout(this.fallback)
    const { state, progress, message } = detail || {}
    if (state === "preparing") {
      const percent = Math.round((progress || 0) * 100)
      this.progressTarget.style.width = `${percent}%`
      this.progressTextTarget.textContent = percent > 0 ? `${percent}%` : ""
    }
    if (state === "failed") this.failedTextTarget.textContent = message || "Tap to Pay on iPhone couldn't be set up. Try again."
    this.show(state || "notSetUp")
  }

  show(name) {
    ;["browser", "checking", "notSetUp", "preparing", "ready", "needsAdmin", "failed"].forEach((panel) => {
      const target = this[`${panel}Target`]
      if (target) target.classList.toggle("hidden", panel !== name)
    })
  }
}
