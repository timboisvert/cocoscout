import { Controller } from "@hotwired/stimulus"

// The Customize modal on a show's payout page (manage/show_payouts/_customize_modal).
// Two ways to pay this event — everyone the same amount, or each person their
// own — and, under the per-person list, a running total against what the
// calculation itself gives. When the calculation splits a fixed pot the
// amounts have to add back up to it before Save unlocks; otherwise the
// difference is just shown.
export default class extends Controller {
    static targets = [
        "mode", "row", "samePanel", "differentPanel",
        "amount", "total", "difference", "warning", "submit"
    ]
    static values = {
        expected: Number,        // the calculation's own total for these payees
        hasExpected: Boolean,    // false when it can't be worked out yet
        fixedPot: Boolean        // equal / shares: the amounts must add up to expected
    }

    connect() {
        this.update()
    }

    // A mode was picked: highlight its row, reveal its panel, and take the
    // other panel's inputs out of the form (disabled = not submitted, not validated).
    update() {
        const mode = this.mode()
        this.rowTargets.forEach(row => {
            const on = row.dataset.mode === mode
            row.classList.toggle("border-pink-500", on)
            row.classList.toggle("bg-pink-50", on)
            row.classList.toggle("border-gray-200", !on)
        })
        if (this.hasSamePanelTarget) this.togglePanel(this.samePanelTarget, mode === "same")
        if (this.hasDifferentPanelTarget) this.togglePanel(this.differentPanelTarget, mode === "different")
        this.recalc()
    }

    recalc() {
        const mode = this.mode()
        let ok = !!mode

        if (mode === "different" && this.hasTotalTarget) {
            const sum = this.amountTargets.reduce((s, input) => s + (parseFloat(input.value) || 0), 0)
            this.totalTarget.textContent = this.money(sum)

            if (this.hasExpectedValue) {
                const diff = Math.round((sum - this.expectedValue) * 100) / 100
                const matches = Math.abs(diff) <= 0.01
                if (this.fixedPotValue) {
                    ok = matches
                    if (this.hasWarningTarget) this.warningTarget.classList.toggle("hidden", matches)
                } else if (this.hasDifferenceTarget) {
                    this.differenceTarget.textContent = matches ? "" : `${diff > 0 ? "+" : "−"}${this.money(Math.abs(diff))} vs calculated`
                }
            }
        }

        if (this.hasSubmitTarget) this.submitTarget.disabled = !ok
    }

    // ---- helpers ------------------------------------------------------------

    mode() {
        const checked = this.modeTargets.find(radio => radio.checked)
        return checked ? checked.value : null
    }

    togglePanel(panel, on) {
        panel.classList.toggle("hidden", !on)
        panel.querySelectorAll("input").forEach(input => { input.disabled = !on })
    }

    money(amount) {
        return "$" + amount.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })
    }
}
