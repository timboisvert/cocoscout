import { Controller } from "@hotwired/stimulus"

// Choosing tickets on a show's page: − / + steppers per ticket type, a live
// total, and — tap the total — a small panel naming every cent: each ticket
// type, the fees, the tax. The math is
// TicketPricing's (our 50¢ per paid ticket, card processing grossed up once
// per order when buyers pay the fees, tax added on top), so the total is what
// checkout charges — before any code — and never more than the ticket prices
// shown added up.
export default class extends Controller {
    static targets = ["row", "count", "input", "minus", "plus", "summary", "total", "totalDetails", "totalSummary", "breakdown", "submit"]
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
        const lines = []
        this.rowTargets.forEach((row) => {
            const input = row.querySelector("[data-ticket-picker-target='input']")
            const n = Number(input.value)
            const price = Number(row.dataset.price)
            count += n
            face += n * price
            tax += n * Number(row.dataset.tax)
            base += n * (price + Number(row.dataset.tax))
            if (price > 0) paid += n
            if (n > 0) lines.push([`${n} × ${row.dataset.name}`, n * price])
            row.querySelector("[data-ticket-picker-target='count']").textContent = n
            row.querySelector("[data-ticket-picker-target='minus']").disabled = n === 0
            row.querySelector("[data-ticket-picker-target='plus']").disabled = n >= Number(row.dataset.max)
        })

        const total = this.totalCents(base, paid)
        this.summaryTarget.textContent = count === 0 ? "Choose your tickets" : `${count} ${count === 1 ? "ticket" : "tickets"}`
        this.totalTarget.textContent = count === 0 ? "" : this.money(total)
        // The lines checkout shows: the tickets, the fees (whatever's left
        // after the tickets and tax), and the tax.
        const fees = total - face - tax
        if (fees > 0) lines.push(["Fees", fees])
        if (tax > 0) lines.push([this.taxLabelValue || "Tax", tax])
        const open = count > 0 && total > 0 && lines.length > 1
        this.renderBreakdown(open ? lines : [], total)
        this.totalTarget.classList.toggle("underline", open)
        this.totalSummaryTarget.classList.toggle("pointer-events-none", !open)
        if (!open) this.totalDetailsTarget.open = false
        this.submitTarget.disabled = count === 0
    }

    renderBreakdown(lines, total) {
        const row = (label, cents, strong) => {
            const div = document.createElement("div")
            div.className = strong ? "flex justify-between gap-4 pt-1 border-t border-gray-200 font-semibold text-gray-900" : "flex justify-between gap-4"
            const dt = document.createElement("dt")
            dt.textContent = label
            const dd = document.createElement("dd")
            dd.className = "tabular-nums"
            dd.textContent = this.money(cents)
            div.append(dt, dd)
            return div
        }
        const rows = lines.map(([label, cents]) => row(label, cents, false))
        if (rows.length > 0) rows.push(row("Total", total, true))
        this.breakdownTarget.replaceChildren(...rows)
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
