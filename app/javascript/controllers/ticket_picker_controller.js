import { Controller } from "@hotwired/stimulus"
import { orderTotalCents, money } from "controllers/lib/ticket_pricing"

// Choosing tickets on a show's page: − / + steppers per ticket type, a live
// total, and — tap the total — a small panel naming every cent: each ticket
// type, the fees, the tax. Coming back from checkout, the buyer's held
// tickets go back into the pickers (the hold is checked with the server and
// reused, or swapped if they change their mind). The math is
// TicketPricing's (our 50¢ per paid ticket, card processing grossed up once
// per order when buyers pay the fees, tax added on top), so the total is what
// checkout charges — before any code — and never more than the ticket prices
// shown added up.
export default class extends Controller {
    static targets = ["row", "count", "input", "minus", "plus", "summary", "total", "totalDetails", "totalSummary", "breakdown", "submit",
        "holdInput", "holdNote", "code"]
    static values = { feeMode: String, platformFee: Number, perMille: Number, fixed: Number, taxLabel: String,
        listingId: Number, holdUrl: String }

    connect() {
        this.render()
        this.restoreHold()
        // Back/forward can show the page from the browser's cache: check again.
        this.onPageShow = (event) => { if (event.persisted) this.restoreHold() }
        window.addEventListener("pageshow", this.onPageShow)
    }

    disconnect() {
        window.removeEventListener("pageshow", this.onPageShow)
        clearInterval(this.holdTimer)
    }

    holdKey() {
        return `cocoscout:ticket-hold:${this.listingIdValue}`
    }

    async restoreHold() {
        let token = null
        try {
            token = window.localStorage.getItem(this.holdKey())
        } catch (_e) {
            return
        }
        if (!token || !this.holdUrlValue) return

        try {
            const response = await fetch(this.holdUrlValue.replace("TOKEN", encodeURIComponent(token)), { headers: { Accept: "application/json" } })
            if (!response.ok) return this.forgetHold()
            const hold = await response.json()
            if (!hold.holding || hold.listing_id !== this.listingIdValue) return this.forgetHold()
            this.applyHold(token, hold)
        } catch (_e) {
            // Without the check the page still works; they just pick again.
        }
    }

    applyHold(token, hold) {
        this.rowTargets.forEach((row) => {
            const held = Number(hold.quantities[row.dataset.tierId] || 0)
            // Their own held seats are theirs to pick again, not taken.
            const left = row.dataset.left === "" ? Infinity : Number(row.dataset.left) + held
            row.dataset.max = Math.min(left, Number(row.dataset.perOrder))
            row.querySelector("[data-ticket-picker-target='input']").value = held
        })
        this.holdInputTarget.value = token
        if (hold.code && !this.hasCodeTarget) {
            const code = document.createElement("input")
            code.type = "hidden"
            code.name = "code"
            code.value = hold.code
            this.element.appendChild(code)
        }
        this.startHoldClock(new Date(hold.expires_at).getTime())
        this.render()
    }

    startHoldClock(expiresAt) {
        clearInterval(this.holdTimer)
        const tick = () => {
            const left = Math.max(0, Math.floor((expiresAt - Date.now()) / 1000))
            if (left === 0) {
                clearInterval(this.holdTimer)
                this.holdNoteTarget.classList.add("hidden")
                this.holdInputTarget.value = ""
                return this.forgetHold()
            }
            const count = this.inputTargets.reduce((sum, input) => sum + Number(input.value), 0)
            this.holdNoteTarget.textContent =
                `Your ${count} ${count === 1 ? "ticket is" : "tickets are"} held for ${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}.`
            this.holdNoteTarget.classList.remove("hidden")
        }
        tick()
        this.holdTimer = setInterval(tick, 1000)
    }

    forgetHold() {
        try {
            window.localStorage.removeItem(this.holdKey())
        } catch (_e) {
            // Nothing to forget.
        }
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
            // A 4-pack admits four: four tickets, four 50¢ fees.
            const admits = Number(row.dataset.admits || 1)
            count += n * admits
            face += n * price
            tax += n * Number(row.dataset.tax)
            base += n * (price + Number(row.dataset.tax))
            if (price > 0) paid += n * admits
            if (n > 0) lines.push([`${n} × ${row.dataset.name}`, n * price])
            // A sold-out type has no steppers.
            const counter = row.querySelector("[data-ticket-picker-target='count']")
            if (counter) counter.textContent = n
            const minus = row.querySelector("[data-ticket-picker-target='minus']")
            if (minus) minus.disabled = n === 0
            const plus = row.querySelector("[data-ticket-picker-target='plus']")
            if (plus) plus.disabled = n >= Number(row.dataset.max)
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
        return orderTotalCents({ base, paid, feeMode: this.feeModeValue, platformFee: this.platformFeeValue,
            perMille: this.perMilleValue, fixed: this.fixedValue })
    }

    money(cents) {
        return money(cents)
    }
}
