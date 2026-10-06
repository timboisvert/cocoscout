import { Controller } from "@hotwired/stimulus"
import { orderTotalCents, money } from "controllers/lib/ticket_pricing"

// Selling at the door (door/show): − / + per ticket type, and what each way
// of paying comes to. Cash is the tickets and their tax; card or phone pay is
// the online price, fees and all (the buyer pays on their own phone).
export default class extends Controller {
    static targets = ["row", "input", "count", "minus", "plus", "cardButton", "cashButton", "compButton"]
    static values = { feeMode: String, platformFee: Number, perMille: Number, fixed: Number }

    connect() {
        this.render()
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
        this.label(this.cardButtonTarget, count === 0 ? "Card or phone pay" : `Card or phone pay · ${money(card)}`)
        this.label(this.cashButtonTarget, count === 0 ? "Cash" : `Cash · ${money(base)}`)
        ;[this.cardButtonTarget, this.cashButtonTarget, this.compButtonTarget].forEach((button) => { button.disabled = count === 0 })
        // A free ticket can't go on a card, and a comp carries no products.
        if (card === 0) this.cardButtonTarget.disabled = true
        if (products > 0) this.compButtonTarget.disabled = true
    }

    label(button, text) {
        const span = button.querySelector("span")
        if (span) span.textContent = text
    }
}
