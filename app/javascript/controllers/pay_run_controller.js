import { Controller } from "@hotwired/stimulus"

// Live totals for the staff pay-run grid. Worked pay is either per-role (when
// approved hours are pulled in — the row carries the computed worked cents on
// data-worked-cents) or the row's default rate×hours. recalc adds bonus +
// reimbursement + tips per row and the grand total in the footer. Cash tips are
// excluded from the amount paid through Stripe.
export default class extends Controller {
    static targets = ["row", "grandTotal", "count"]

    connect() {
        this.recalc()
    }

    recalc() {
        let grand = 0
        let paying = 0
        this.rowTargets.forEach(row => {
            const rate = (parseFloat(row.dataset.rate || "0") || 0) / 100
            const val = f => parseFloat(row.querySelector(`[data-pay-field="${f}"]`)?.value || "0") || 0
            // Pulled per-role pay takes precedence over rate×hours when present.
            const worked = row.dataset.workedCents ? (parseFloat(row.dataset.workedCents) / 100) : rate * val("hours")
            const total = worked + val("bonus") + val("reimbursement") + val("tips")
            const cell = row.querySelector("[data-pay-total]")
            if (cell) cell.textContent = this.fmt(total)
            if (total > 0 && row.dataset.payable === "true") { grand += total; paying += 1 }
        })
        if (this.hasGrandTotalTarget) this.grandTotalTarget.textContent = this.fmt(grand)
        if (this.hasCountTarget) this.countTarget.textContent = paying
    }

    fmt(n) {
        return "$" + (Number.isFinite(n) ? n : 0).toFixed(2)
    }
}
