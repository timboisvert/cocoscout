import { Controller } from "@hotwired/stimulus"

// Checkout for a ticket order (TicketCheckoutsController). Stripe's Payment
// Element is mounted before any PaymentIntent exists ("deferred" mode); on
// submit we send the buyer's details, the server creates the intent (or
// finishes a free order) and hands back its client secret, and Stripe
// confirms the payment and returns the buyer to the done page. Also counts
// down the ten-minute hold on their seats.
export default class extends Controller {
    static targets = ["form", "payment", "error", "submit", "countdown"]
    static values = {
        publishableKey: String,
        amount: Number,
        free: Boolean,
        returnUrl: String,
        expiresAt: String
    }

    connect() {
        this.startCountdown()
        if (this.freeValue) return

        if (!window.Stripe || !this.publishableKeyValue) {
            this.showError("Card payments aren't available right now. Please try again later.")
            this.submitTarget.disabled = true
            return
        }
        this.stripe = window.Stripe(this.publishableKeyValue)
        this.elements = this.stripe.elements({
            mode: "payment",
            amount: this.amountValue,
            currency: "usd",
            appearance: {
                theme: "stripe",
                variables: { colorPrimary: "#ec4899", borderRadius: "8px", fontFamily: "Inter, system-ui, sans-serif" }
            }
        })
        this.elements.create("payment", { layout: "tabs" }).mount(this.paymentTarget)
    }

    disconnect() {
        clearInterval(this.timer)
    }

    async submit(event) {
        event.preventDefault()
        this.hideError()
        this.busy(true)

        try {
            if (!this.freeValue) {
                const { error } = await this.elements.submit()
                if (error) return this.fail(error.message)
            }

            const response = await fetch(this.formTarget.action, {
                method: "POST",
                headers: { "Accept": "application/json", "X-CSRF-Token": this.csrfToken() },
                body: new FormData(this.formTarget)
            })
            const data = await response.json()
            if (data.error) return this.fail(data.error)
            if (data.redirect) return window.location.assign(data.redirect)

            const { error } = await this.stripe.confirmPayment({
                elements: this.elements,
                clientSecret: data.client_secret,
                confirmParams: { return_url: this.returnUrlValue }
            })
            // Only reached when confirming failed; success redirects away.
            if (error) this.fail(error.message)
        } catch (_e) {
            this.fail("Something went wrong. Please try again.")
        }
    }

    startCountdown() {
        if (!this.expiresAtValue || !this.hasCountdownTarget) return

        const expiresAt = new Date(this.expiresAtValue).getTime()
        const tick = () => {
            const left = Math.max(0, Math.floor((expiresAt - Date.now()) / 1000))
            if (left === 0) {
                clearInterval(this.timer)
                this.countdownTarget.textContent = "Your hold on these seats ran out."
                this.submitTarget.disabled = true
                window.location.reload()
                return
            }
            const minutes = Math.floor(left / 60)
            const seconds = String(left % 60).padStart(2, "0")
            this.countdownTarget.textContent = `Your seats are held for ${minutes}:${seconds}.`
        }
        tick()
        this.timer = setInterval(tick, 1000)
    }

    fail(message) {
        this.showError(message)
        this.busy(false)
    }

    busy(on) {
        this.submitTarget.disabled = on
        this.submitTarget.classList.toggle("opacity-60", on)
    }

    showError(message) {
        this.errorTarget.textContent = message
        this.errorTarget.classList.remove("hidden")
    }

    hideError() {
        this.errorTarget.classList.add("hidden")
    }

    csrfToken() {
        return document.querySelector('meta[name="csrf-token"]')?.content || ""
    }
}
