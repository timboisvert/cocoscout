import { Controller } from "@hotwired/stimulus"

// Checkout for a ticket order (TicketCheckoutsController). Stripe's Payment
// Element is mounted before any PaymentIntent exists ("deferred" mode); on
// submit we send the buyer's details, the server creates the intent (or
// finishes a free order) and hands back its client secret, and Stripe
// confirms the payment and returns the buyer to the done page. Also counts
// down the ten-minute hold on their seats, and remembers the hold in the
// browser so going back to the show's page puts the tickets back
// (ticket_picker_controller).
export default class extends Controller {
    static targets = ["form", "payment", "error", "submit", "countdown", "summary",
                      "products", "productRow", "productCount", "productMinus", "productPlus"]
    static values = {
        publishableKey: String,
        amount: Number,
        free: Boolean,
        returnUrl: String,
        expiresAt: String,
        listingId: Number,
        token: String,
        itemsUrl: String
    }

    connect() {
        this.rememberHold()
        this.startCountdown()
        this.renderProducts()
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

    rememberHold() {
        if (!this.listingIdValue || !this.tokenValue) return
        try {
            window.localStorage.setItem(`cocoscout:ticket-hold:${this.listingIdValue}`, this.tokenValue)
        } catch (_e) {
            // Private windows can refuse storage; checkout works without it.
        }
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

    // Products (a bottle for the table): − / + per product. Each change is
    // saved to the hold straight away, and the summary, the total and the
    // amount Stripe will charge follow. A total that goes from free to paid
    // (or back) needs the payment box, so the page reloads for that.
    moreProducts(event) {
        this.stepProduct(event, 1)
    }

    fewerProducts(event) {
        this.stepProduct(event, -1)
    }

    stepProduct(event, by) {
        const row = event.currentTarget.closest("[data-ticket-checkout-target='productRow']")
        const count = row.querySelector("[data-ticket-checkout-target='productCount']")
        const max = Number(row.dataset.max)
        count.textContent = Math.min(max, Math.max(0, Number(count.textContent) + by))
        this.renderProducts()
        clearTimeout(this.itemsTimer)
        this.itemsTimer = setTimeout(() => this.saveProducts(), 350)
    }

    renderProducts() {
        this.productRowTargets.forEach((row) => {
            const n = Number(row.querySelector("[data-ticket-checkout-target='productCount']").textContent)
            row.querySelector("[data-ticket-checkout-target='productMinus']").disabled = n === 0
            row.querySelector("[data-ticket-checkout-target='productPlus']").disabled = n >= Number(row.dataset.max)
        })
    }

    async saveProducts() {
        if (!this.itemsUrlValue) return
        const products = {}
        this.productRowTargets.forEach((row) => {
            products[row.dataset.productId] = Number(row.querySelector("[data-ticket-checkout-target='productCount']").textContent)
        })
        this.hideError()
        this.busy(true)
        try {
            const response = await fetch(this.itemsUrlValue, {
                method: "PATCH",
                headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": this.csrfToken() },
                body: JSON.stringify({ products })
            })
            const data = await response.json()
            if (data.error) return this.fail(data.error)
            if (this.hasSummaryTarget) this.summaryTarget.innerHTML = data.summary_html
            const wasFree = this.amountValue === 0
            this.amountValue = data.total_cents
            if (wasFree !== (data.total_cents === 0)) return window.location.reload()
            if (this.elements) this.elements.update({ amount: data.total_cents })
            this.relabelSubmit(data.total_cents)
            this.busy(false)
        } catch (_e) {
            this.fail("Couldn't save that. Please try again.")
        }
    }

    relabelSubmit(cents) {
        const span = this.submitTarget.querySelector("span") || this.submitTarget
        const prefix = this.submitTarget.dataset.payPrefix
        if (prefix === undefined || prefix === "") return
        span.textContent = `${prefix}$${(cents / 100).toFixed(2)}`
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
            this.countdownTarget.textContent = `Held for you for ${minutes}:${seconds}`
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
