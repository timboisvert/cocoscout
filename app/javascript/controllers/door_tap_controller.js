import { Controller } from "@hotwired/stimulus"

// The door phone taking a tap (door/tap). On connect it asks the app to take
// the payment (door-tap:pay, answered by bridge--tap-to-pay); when the app
// says the tap went through it settles the order with the server, and all
// the while it watches the order like a card-or-phone sale, in case Stripe's
// webhook settled it first. A failed tap shows why and offers another go.
export default class extends Controller {
    static targets = ["waiting", "paid", "paidText", "expired", "countdown", "prompt", "error", "retry"]
    static values = { statusUrl: String, settleUrl: String, expiresAt: String }

    connect() {
        this.timer = setInterval(() => this.poll(), 2000)
        this.clock = setInterval(() => this.tick(), 1000)
        this.tick()
        this.retry()
    }

    disconnect() {
        clearInterval(this.timer)
        clearInterval(this.clock)
        clearTimeout(this.asking)
    }

    // Asks the app for the tap; nothing answers in a browser.
    retry() {
        this.errorTarget.classList.add("hidden")
        this.retryTarget.classList.add("hidden")
        this.promptTarget.textContent = "Hold their card or phone to the top of this phone"
        this.askApp()
    }

    // The app's bridge isn't listening yet when the page first connects:
    // ask until it takes the tap (bridge--tap-to-pay marks the event
    // handled), for a few seconds.
    askApp(attempt = 0) {
        clearTimeout(this.asking)
        const event = this.dispatch("pay")
        if (!event.defaultPrevented && attempt < 20) {
            this.asking = setTimeout(() => this.askApp(attempt + 1), 250)
        }
    }

    // tap-to-pay:done — { status: "paid" | "failed" | "canceled", message, paymentIntentId }.
    async done({ detail }) {
        if (detail.status === "paid") {
            await this.settle(detail.paymentIntentId)
        } else if (detail.status === "failed") {
            this.fail(detail.message || "The tap didn't go through.")
        } else {
            this.fail("Canceled before the tap.")
        }
    }

    async settle(paymentIntentId) {
        this.promptTarget.textContent = "Confirming with Stripe…"
        try {
            const token = document.querySelector("meta[name='csrf-token']")?.content
            const response = await fetch(this.settleUrlValue, {
                method: "POST",
                headers: { Accept: "application/json", "Content-Type": "application/json", "X-CSRF-Token": token },
                body: JSON.stringify({ payment_intent_id: paymentIntentId })
            })
            const data = await response.json()
            if (data.status === "paid") this.show("paid", data.message)
            else this.fail(data.error || "Stripe hasn't confirmed the payment yet.")
        } catch (_e) {
            this.fail("Lost the connection while confirming. Try again.")
        }
    }

    fail(message) {
        this.promptTarget.textContent = "Not paid"
        this.errorTarget.textContent = message
        this.errorTarget.classList.remove("hidden")
        this.retryTarget.classList.remove("hidden")
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
