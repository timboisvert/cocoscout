import { Controller } from "@hotwired/stimulus"

// Push notifications on this phone, in the app: the Notifications settings
// row and the one-time card on Home. bridge/push_controller says where they
// stand (push:status); this shows the matching part, each a [data-push-state]
// target naming "ask" (never asked), "on", or "off" (turned off in iPhone
// Settings). Stays hidden in a browser, where nothing ever says.
//
// dismissKey: a card that "Not now" puts away for good on this phone.
export default class extends Controller {
  static targets = ["state"]
  static values = { dismissKey: String }

  connect() {
    if (window.cocoscoutPushStatus) this.show(window.cocoscoutPushStatus)
  }

  update({ detail: { status } }) {
    this.show(status)
  }

  show(status) {
    if (this.dismissed()) return

    const state = status === "notDetermined" ? "ask" : status === "denied" ? "off" : "on"
    let any = false
    this.stateTargets.forEach((target) => {
      const match = target.dataset.pushState.split(" ").includes(state)
      target.classList.toggle("hidden", !match)
      any ||= match
    })
    this.element.classList.toggle("hidden", !any)
  }

  request() {
    window.dispatchEvent(new CustomEvent("push:request"))
  }

  openSettings() {
    window.dispatchEvent(new CustomEvent("push:open-settings"))
  }

  dismiss() {
    try { window.localStorage.setItem(this.storageKey, "1") } catch { /* fine without */ }
    this.element.classList.add("hidden")
  }

  dismissed() {
    if (!this.hasDismissKeyValue) return false
    try { return window.localStorage.getItem(this.storageKey) === "1" } catch { return false }
  }

  get storageKey() {
    return `cocoscout:push-dismissed:${this.dismissKeyValue}`
  }
}
