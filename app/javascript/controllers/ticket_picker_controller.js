import { Controller } from "@hotwired/stimulus"

// Choosing tickets on a show's page: − / + steppers per ticket type, a live
// total, and the tickets · fees · tax lines under it. The math is
// TicketPricing's (our 50¢ per paid ticket, card processing grossed up once
// per order when buyers pay the fees, tax added on top), so the total is what
// checkout charges — before any code — and never more than the ticket prices
// shown added up.
export default class extends Controller {
    static targets = ["row", "count", "input", "minus", "plus", "summary", "total", "breakdown", "submit"]
    static values = { feeMode: String, platformFee: Number, perMille: Number, fixed: Number, taxLabel: String }

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
        let face = 0
        let tax = 0
        this.rowTargets.forEach((row) => {
            const input = row.querySelector("[data-ticket-picker-target='input']")
            const n = Number(input.value)
            const price = Number(row.dataset.price)
            count += n
            face += n * price
            tax += n * Number(row.dataset.tax)
            base += n * (price + Number(row.dataset.tax))
            if (price > 0) paid += n
            row.querySelector("[data-ticket-picker-target='count']").textContent = n
            row.querySelector("[data-ticket-picker-target='minus']").disabled = n === 0
            row.querySelector("[data-ticket-picker-target='plus']").disabled = n >= Number(row.dataset.max)
        })

        const total = this.totalCents(base, paid)
        this.summaryTarget.textContent = count === 0 ? "Choose your tickets" : `${count} ${count === 1 ? "ticket" : "tickets"}`
        this.totalTarget.textContent = count === 0 ? "" : this.money(total)
        // The same lines checkout shows: tickets, fees (whatever's left after
        // the tickets and tax), and tax.
        const fees = total - face - tax
        const parts = count === 0 || total === 0 ? [] : [`Tickets ${this.money(face)}`]
        if (count > 0 && fees > 0) parts.push(`Fees ${this.money(fees)}`)
        if (count > 0 && tax > 0) parts.push(`${this.taxLabelValue || "Tax"} ${this.money(tax)}`)
        this.breakdownTarget.textContent = parts.length > 1 ? parts.join(" · ") : ""
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
