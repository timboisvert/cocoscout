import { Controller } from "@hotwired/stimulus"

// Live totals for the staff pay-run grid. Each row carries the hourly rate (in
// cents) on data-rate; recalc computes rate×hours + bonus + reimbursement +
// tips per row and the grand total in the footer. Cash tips are excluded from
// the amount paid through Stripe.
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
            const total = rate * val("hours") + val("bonus") + val("reimbursement") + val("tips")
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
