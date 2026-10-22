import { Controller } from "@hotwired/stimulus"

// Lets the user switch the compact inbox between density modes
// (compact / cozy / comfortable). The choice is saved in localStorage and
// re-applied on connect, so it persists across inboxes and visits.
export default class extends Controller {
    static targets = ["list", "button"]
    static values = { storageKey: { type: String, default: "cocoscout:message-density" } }

    MODES = ["compact", "cozy", "comfortable"]

    connect() {
        this.apply(this.stored())
    }

    // One icon button (the one-line filters): each tap moves to the next mode.
    cycle() {
        const current = this.stored()
        const mode = this.MODES[(this.MODES.indexOf(current) + 1) % this.MODES.length]
        try { localStorage.setItem(this.storageKeyValue, mode) } catch (_) { /* ignore */ }
        this.apply(mode)
    }

    set(event) {
        const mode = event.currentTarget.dataset.mode
        if (!this.MODES.includes(mode)) return
        try { localStorage.setItem(this.storageKeyValue, mode) } catch (_) { /* ignore */ }
        this.apply(mode)
    }

    apply(mode) {
        if (!this.MODES.includes(mode)) mode = "compact"
        if (this.hasListTarget) {
            this.MODES.forEach(m => this.listTarget.classList.remove(`msg-density-${m}`))
            this.listTarget.classList.add(`msg-density-${mode}`)
        }
        this.buttonTargets.forEach(btn => {
            const active = btn.dataset.mode === mode
            btn.classList.toggle("bg-pink-500", active)
            btn.classList.toggle("text-white", active)
            btn.classList.toggle("bg-gray-100", !active)
            btn.classList.toggle("text-gray-700", !active)
        })
    }

    stored() {
        try { return localStorage.getItem(this.storageKeyValue) || "compact" }
        catch (_) { return "compact" }
    }
}
