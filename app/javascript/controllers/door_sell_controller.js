import { Controller } from "@hotwired/stimulus"
import { orderTotalCents, money } from "controllers/lib/ticket_pricing"

// Selling at the door (door/show): − / + per ticket type, and what each way
// of paying comes to. Cash is the tickets and their tax; card or phone pay is
// the online price, fees and all (the buyer pays on their own phone).
export default class extends Controller {
    static targets = ["row", "input", "count", "minus", "plus", "cardButton", "cashButton", "compButton", "tapButton", "buyerName", "buyerEmail", "buyerError"]
    static values = { feeMode: String, platformFee: Number, perMille: Number, fixed: Number, tapPerMille: Number, tapFixed: Number,
                      cardLabel: { type: String, default: "Card or phone pay" }, tapLabel: { type: String, default: "Tap to Pay on iPhone" },
                      buyerRequired: Boolean }

    connect() {
        this.render()
        this.checkBuyer = this.checkBuyer.bind(this)
        this.element.addEventListener("submit", this.checkBuyer)
    }

    disconnect() {
        this.element.removeEventListener("submit", this.checkBuyer)
    }

    // Selling ahead of the door opening is presale: cash, tap and comp need
    // their name and email here. Card asks on the buyer's own phone.
    checkBuyer(event) {
        if (!this.buyerRequiredValue || !this.hasBuyerNameTarget) return
        if (event.submitter?.value === "card") return

        const email = this.buyerEmailTarget
        const missing = !this.buyerNameTarget.value.trim() ? this.buyerNameTarget
            : (!email.value.trim() || !email.checkValidity()) ? email : null
        this.buyerErrorTarget.classList.toggle("hidden", !missing)
        if (missing) {
            event.preventDefault()
            event.stopImmediatePropagation()
            missing.focus()
        }
    }

    increment(event) {
        this.step(event, 1)
    }

    decrement(event) {
        this.step(event, -1)
    }

    step(event, by) {
        const row = event.currentTarget.closest("[data-door-sell-target='row']")
        const input = row.querySelector("[data-door-sell-target='input']")
        const max = Number(row.dataset.max)
        input.value = Math.min(max, Math.max(0, Number(input.value) + by))
        this.render()
    }

    render() {
        let count = 0
        let base = 0
        let paid = 0
        let products = 0
        this.rowTargets.forEach((row) => {
            const n = Number(row.querySelector("[data-door-sell-target='input']").value)
            const price = Number(row.dataset.price)
            const product = row.dataset.product === "1"
            // A 4-pack admits four: four tickets, four 50¢ fees.
            const admits = Number(row.dataset.admits || 1)
            // A product (a bottle) adds its price and tax, never our 50¢, and
            // only goes with a ticket.
            if (product) products += n
            else count += n * admits
            base += n * (price + Number(row.dataset.tax))
            if (price > 0 && !product) paid += n * admits
            row.querySelector("[data-door-sell-target='count']").textContent = n
            row.querySelector("[data-door-sell-target='minus']").disabled = n === 0
            row.querySelector("[data-door-sell-target='plus']").disabled = n >= Number(row.dataset.max)
        })

        const card = orderTotalCents({ base, paid, feeMode: this.feeModeValue, platformFee: this.platformFeeValue,
            perMille: this.perMilleValue, fixed: this.fixedValue })
        this.label(this.cardButtonTarget, count === 0 ? this.cardLabelValue : `${this.cardLabelValue} · ${money(card)}`)
        this.label(this.cashButtonTarget, count === 0 ? "Cash" : `Cash · ${money(base)}`)
        ;[this.cardButtonTarget, this.cashButtonTarget, this.compButtonTarget].forEach((button) => { button.disabled = count === 0 })
        // Tap to Pay (the app): the same sale at Stripe's in-person rate.
        if (this.hasTapButtonTarget) {
            const tap = orderTotalCents({ base, paid, feeMode: this.feeModeValue, platformFee: this.platformFeeValue,
                perMille: this.tapPerMilleValue, fixed: this.tapFixedValue })
            // Never greyed out (Apple's Tap to Pay 5.3): with nothing picked it says so instead.
            this.label(this.tapButtonTarget, count === 0 ? this.tapLabelValue : `${this.tapLabelValue} · ${money(tap)}`)
        }
        // A free ticket can't go on a card, and a comp carries no products.
        if (card === 0) this.cardButtonTarget.disabled = true
        if (products > 0) this.compButtonTarget.disabled = true
    }

    label(button, text) {
        const span = button.querySelector("span")
        if (span) span.textContent = text
    }
}
