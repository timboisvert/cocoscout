import { Controller } from "@hotwired/stimulus"

// The door phone while a buyer pays on theirs (door/card): asks every two
// seconds how the order stands, and flips to Paid (they're checked in) or to
// "the hold ran out".
export default class extends Controller {
    static targets = ["waiting", "paid", "paidText", "expired", "countdown"]
    static values = { statusUrl: String, expiresAt: String }

    connect() {
        this.poll()
        this.timer = setInterval(() => this.poll(), 2000)
        this.clock = setInterval(() => this.tick(), 1000)
        this.tick()
    }

    disconnect() {
        clearInterval(this.timer)
        clearInterval(this.clock)
    }

    tick() {
        if (!this.hasCountdownTarget || !this.expiresAtValue) return
        const left = Math.max(0, Math.floor((new Date(this.expiresAtValue).getTime() - Date.now()) / 1000))
        this.countdownTarget.textContent = `${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}`
    }

    async poll() {
        try {
            const response = await fetch(this.statusUrlValue, { headers: { Accept: "application/json" } })
            if (!response.ok) return
            const data = await response.json()
            if (data.status === "paid") this.show("paid", data.message)
            else if (data.status === "expired") this.show("expired")
        } catch (_e) {
            // A dropped connection at the door: try again next tick.
        }
    }

    show(state, message) {
        clearInterval(this.timer)
        clearInterval(this.clock)
        this.waitingTarget.classList.add("hidden")
        if (state === "paid") {
            if (message) this.paidTextTarget.textContent = message
            this.paidTarget.classList.remove("hidden")
        } else {
            this.expiredTarget.classList.remove("hidden")
        }
    }
}
