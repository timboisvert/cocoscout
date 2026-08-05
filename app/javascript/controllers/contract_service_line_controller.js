import { Controller } from "@hotwired/stimulus"

// One service line in the contract wizard's Services step. Progressive:
// checking the service reveals its config; per-event lines list the booked
// dates with hours each, and every input keeps the per-event and total cost
// estimates live. The settlement choice only applies when they pay us, so it
// hides for outgoing lines.
export default class extends Controller {
    static targets = ["include", "body", "quantity", "price", "direction", "settlementWrap",
                      "eventInclude", "eventHours", "eventCost", "eventSummary", "total", "headerTotal"]
    static values = { unit: String, perEvent: Boolean }

    connect() {
        this.toggle()
    }

    toggle() {
        const on = this.hasIncludeTarget && this.includeTarget.checked
        if (this.hasBodyTarget) this.bodyTarget.classList.toggle("hidden", !on)
        this.recalc()
    }

    directionChanged() {
        if (!this.hasSettlementWrapTarget || !this.hasDirectionTarget) return
        this.settlementWrapTarget.classList.toggle("hidden", this.directionTarget.value === "outgoing")
    }

    checkAllEvents(event) {
        if (event) event.preventDefault()
        this.eventIncludeTargets.forEach(cb => cb.checked = true)
        this.recalc()
    }

    checkNoEvents(event) {
        if (event) event.preventDefault()
        this.eventIncludeTargets.forEach(cb => cb.checked = false)
        this.recalc()
    }

    recalc() {
        const on = this.hasIncludeTarget && this.includeTarget.checked
        const price = this.hasPriceTarget ? parseFloat(this.priceTarget.value) || 0 : 0
        let total = 0

        if (this.perEventValue) {
            let events = 0
            let hoursTotal = 0
            this.eventIncludeTargets.forEach((cb, idx) => {
                const hoursInput = this.eventHoursTargets[idx]
                const hours = hoursInput ? parseFloat(hoursInput.value) || 0 : 1
                const cost = this.unitValue === "hourly" ? hours * price : price
                const costEl = this.eventCostTargets[idx]
                if (costEl) costEl.textContent = cb.checked ? this.money(cost) : "—"
                if (hoursInput && hoursInput.type !== "hidden") hoursInput.disabled = !cb.checked
                if (cb.checked) {
                    events += 1
                    hoursTotal += hours
                    total += cost
                }
            })
            if (this.hasEventSummaryTarget) {
                const hoursPart = this.unitValue === "hourly" ? ` · ${this.trim(hoursTotal)} hrs` : ""
                this.eventSummaryTarget.textContent = events > 0
                    ? `${events} ${events === 1 ? "event" : "events"}${hoursPart}`
                    : "No events selected"
            }
        } else {
            const qty = this.hasQuantityTarget ? parseFloat(this.quantityTarget.value) || 0 : 1
            total = qty * price
        }

        if (this.hasTotalTarget) this.totalTarget.textContent = this.money(total)
        if (this.hasHeaderTotalTarget) this.headerTotalTarget.textContent = on && total > 0 ? this.money(total) : ""
    }

    money(n) {
        return `$${n.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ",")}`
    }

    trim(n) {
        return Number.isInteger(n) ? String(n) : n.toFixed(1)
    }
}
