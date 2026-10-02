import { Controller } from "@hotwired/stimulus"

// Choosing tickets on a show's page: − / + steppers per ticket type, and a
// live total. The total uses the same math as TicketPricing (our 50¢ per paid
// ticket, card processing grossed up once per order when buyers pay the
// fees), so what the button says is what checkout charges — before any code.
export default class extends Controller {
    static targets = ["row", "count", "input", "minus", "plus", "summary", "total", "submit"]
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
        const row = event.currentTarget.closest("[data-ticket-picker-target='row']")
        const input = row.querySelector("[data-ticket-picker-target='input']")
        const max = Number(row.dataset.max)
        input.value = Math.min(max, Math.max(0, Number(input.value) + by))
        this.render()
    }

    render() {
        let count = 0
        let base = 0
        let paid = 0
        this.rowTargets.forEach((row) => {
            const input = row.querySelector("[data-ticket-picker-target='input']")
            const n = Number(input.value)
            const price = Number(row.dataset.price)
            const tax = Number(row.dataset.tax)
            count += n
            base += n * (price + tax)
            if (price > 0) paid += n
            row.querySelector("[data-ticket-picker-target='count']").textContent = n
            row.querySelector("[data-ticket-picker-target='minus']").disabled = n === 0
            row.querySelector("[data-ticket-picker-target='plus']").disabled = n >= Number(row.dataset.max)
        })

        const total = this.totalCents(base, paid)
        this.summaryTarget.textContent = count === 0 ? "Choose your tickets" : `${count} ${count === 1 ? "ticket" : "tickets"}`
        this.totalTarget.textContent = count === 0 ? "" : this.money(total)
        this.submitTarget.disabled = count === 0
    }

    totalCents(base, paid) {
        if (base === 0) return 0
        if (this.feeModeValue !== "buyer") return base
        return this.grossUp(base + this.platformFeeValue * paid)
    }

    processing(total) {
        return Math.floor((total * this.perMilleValue + 500) / 1000) + this.fixedValue
    }

    // The smallest charge that leaves exactly `needed` after processing.
    grossUp(needed) {
        let total = Math.floor(((needed + this.fixedValue) * 1000) / (1000 - this.perMilleValue)) - 2
        while (total - this.processing(total) < needed) total += 1
        return total
    }

    money(cents) {
        return "$" + (cents / 100).toFixed(2)
    }
}
