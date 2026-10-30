import { Controller } from "@hotwired/stimulus"

// Checkout, for a ticket order (TicketCheckoutsController) or a course
// registration (My::CourseCheckoutsController). Stripe's Payment Element is
// mounted before any PaymentIntent exists ("deferred" mode); on submit we
// send the buyer's details, the server creates the intent (or finishes a
// free order) and hands back its client secret, and Stripe confirms the
// payment and returns the buyer to the done page. Also counts down the
// ten-minute hold, and (given a holdKey) remembers the hold in the browser
// so going back to the show's page puts the tickets back
// (ticket_picker_controller).
export default class extends Controller {
    static targets = ["form", "payment", "paymentTitle", "error", "submit", "countdown", "summary",
                      "products", "productRow", "productCount", "productMinus", "productPlus",
                      "gift", "giftClosed", "giftOpen", "giftCode", "giftApply", "giftError"]
    static values = {
        publishableKey: String,
        amount: Number,
        free: Boolean,
        returnUrl: String,
        expiresAt: String,
        holdKey: String,
        token: String,
        itemsUrl: String,
        giftUrl: String
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
        if (!this.holdKeyValue || !this.tokenValue) return
        try {
            window.localStorage.setItem(this.holdKeyValue, this.tokenValue)
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
        const row = event.currentTarget.closest("[data-checkout-target='productRow']")
        const count = row.querySelector("[data-checkout-target='productCount']")
        const max = Number(row.dataset.max)
        count.textContent = Math.min(max, Math.max(0, Number(count.textContent) + by))
        this.renderProducts()
        clearTimeout(this.itemsTimer)
        this.itemsTimer = setTimeout(() => this.saveProducts(), 350)
    }

    renderProducts() {
        this.productRowTargets.forEach((row) => {
            const n = Number(row.querySelector("[data-checkout-target='productCount']").textContent)
            row.querySelector("[data-checkout-target='productMinus']").disabled = n === 0
            row.querySelector("[data-checkout-target='productPlus']").disabled = n >= Number(row.dataset.max)
        })
    }

    async saveProducts() {
        if (!this.itemsUrlValue) return
        // Products and deals on another show share the steppers; each row
        // says which it is.
        const products = {}
        const deals = {}
        this.productRowTargets.forEach((row) => {
            const count = Number(row.querySelector("[data-checkout-target='productCount']").textContent)
            if (row.dataset.kind === "deal") deals[row.dataset.offerId] = count
            else products[row.dataset.productId] = count
        })
        this.hideError()
        this.busy(true)
        try {
            const response = await fetch(this.itemsUrlValue, {
                method: "PATCH",
                headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": this.csrfToken() },
                body: JSON.stringify(Object.keys(deals).length ? { products, deals } : { products })
            })
            const data = await response.json()
            if (data.error) return this.fail(data.error)
            this.applyState(data)
        } catch (_e) {
            this.fail("Couldn't save that. Please try again.")
        }
    }

    // The order changed on the server (products, a gift certificate): the
    // summary, the amount the card pays (card_cents: the total less what a
    // certificate covers), Stripe's amount and the button follow. Going from
    // nothing-to-pay to paying (or back) needs the payment box, so the page
    // reloads for that. A certificate coming on or off also renames the
    // Payment heading.
    applyState(data) {
        const cents = data.card_cents ?? data.total_cents
        if (this.hasSummaryTarget) this.summaryTarget.innerHTML = data.summary_html
        const wasFree = this.amountValue === 0
        this.amountValue = cents
        if (wasFree !== (cents === 0)) return window.location.reload()
        if (this.elements) this.elements.update({ amount: cents })
        if (this.hasPaymentTitleTarget && data.card_cents !== undefined && data.card_cents !== data.total_cents) {
            this.paymentTitleTarget.textContent = `Pay the rest · $${(cents / 100).toFixed(2)}`
        } else if (this.hasPaymentTitleTarget) {
            this.paymentTitleTarget.textContent = "Payment"
        }
        this.relabelSubmit(cents)
        this.busy(false)
    }

    // A gift certificate (TicketCheckoutsController#apply_gift_certificate):
    // "Have a gift certificate?" opens the code field; Apply sends the code;
    // Remove (in the summary) takes it off again.
    openGift(event) {
        event?.preventDefault()
        this.giftClosedTarget.classList.add("hidden")
        this.giftOpenTarget.classList.remove("hidden")
        this.giftCodeTarget.focus()
    }

    async applyGift(event) {
        event?.preventDefault()
        const code = this.giftCodeTarget.value.trim()
        if (!code) return this.giftFail("Type the code from the certificate.")
        await this.sendGift("POST", { code })
    }

    async removeGift(event) {
        event?.preventDefault()
        await this.sendGift("DELETE")
    }

    async sendGift(method, body) {
        if (!this.giftUrlValue) return
        this.hideError()
        this.giftError(null)
        this.busy(true)
        if (this.hasGiftApplyTarget) this.giftApplyTarget.disabled = true
        try {
            const response = await fetch(this.giftUrlValue, {
                method,
                headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": this.csrfToken() },
                body: body ? JSON.stringify(body) : undefined
            })
            const data = await response.json()
            if (data.error) return this.giftFail(data.error)
            if (method === "POST") {
                // Applied: the summary shows it; the field goes away.
                this.giftOpenTarget.classList.add("hidden")
                this.giftClosedTarget.classList.add("hidden")
            } else {
                this.giftCodeTarget.value = ""
                this.giftClosedTarget.classList.remove("hidden")
            }
            this.applyState(data)
        } catch (_e) {
            this.giftFail("Couldn't check that code. Please try again.")
        } finally {
            if (this.hasGiftApplyTarget) this.giftApplyTarget.disabled = false
        }
    }

    giftFail(message) {
        this.giftError(message)
        this.busy(false)
    }

    giftError(message) {
        if (!this.hasGiftErrorTarget) return
        this.giftErrorTarget.textContent = message || ""
        this.giftErrorTarget.classList.toggle("hidden", !message)
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
                this.countdownTarget.textContent = "Your hold ran out."
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
