import { Controller } from "@hotwired/stimulus"

// The amounts for one payout approach (manage/payout_calculation_wizard/_amounts_fields).
// Reveals the optional panels (guaranteed minimum, shares, the three per-act
// modes) and manages the per-act rows: a positional schedule ("1st act pays…")
// that renumbers itself, and a table of "N acts pays $X" tiers.
export default class extends Controller {
    static targets = [
        "minimumPanel",
        "sharesPanel",
        "perActSimple", "perActSchedule", "perActTiers",
        "actRatesList", "actRateRow", "actRateLabel", "actRateTemplate",
        "actTiersList", "actTierRow", "actTierTemplate"
    ]

    connect() {
        this.actTierIndex = this.actTierRowTargets.length
        this.renumberActRates()
    }

    // ---- per ticket ---------------------------------------------------------

    toggleMinimum(event) {
        if (!this.hasMinimumPanelTarget) return
        this.minimumPanelTarget.classList.toggle("hidden", !event.target.checked)
    }

    // ---- share --------------------------------------------------------------

    updateSplit() {
        if (!this.hasSharesPanelTarget) return
        this.sharesPanelTarget.classList.toggle("hidden", this.checkedValue("distribution[split]") !== "shares")
    }

    // ---- per act ------------------------------------------------------------

    updateActMode() {
        const mode = this.checkedValue("distribution[act_mode]") || "schedule"
        if (this.hasPerActSimpleTarget) this.perActSimpleTarget.classList.toggle("hidden", mode !== "simple")
        if (this.hasPerActScheduleTarget) this.perActScheduleTarget.classList.toggle("hidden", mode !== "schedule")
        if (this.hasPerActTiersTarget) this.perActTiersTarget.classList.toggle("hidden", mode !== "tiers")
    }

    // The schedule rows are positional — the first row is the first act — so
    // adding or removing one renumbers the labels.
    addActRate(event) {
        if (event) event.preventDefault()
        if (!this.hasActRatesListTarget || !this.hasActRateTemplateTarget) return

        this.actRatesListTarget.appendChild(this.actRateTemplateTarget.content.cloneNode(true))
        this.renumberActRates()
        this.focusLastInput(this.actRatesListTarget)
    }

    removeActRate(event) {
        event.preventDefault()
        event.target.closest('[data-payout-calculation-amounts-target="actRateRow"]')?.remove()
        this.renumberActRates()
    }

    renumberActRates() {
        this.actRateLabelTargets.forEach((label, index) => {
            label.textContent = `${this.ordinalize(index + 1)} act pays`
        })
    }

    // Add another "N acts pays $X" row, one act past the last row.
    addActTier(event) {
        if (event) event.preventDefault()
        if (!this.hasActTiersListTarget || !this.hasActTierTemplateTarget) return

        const index = this.actTierIndex++
        const lastRow = this.actTierRowTargets[this.actTierRowTargets.length - 1]
        const nextActs = lastRow ? (parseInt(lastRow.querySelector('input[type="number"]').value, 10) || 0) + 1 : 1

        const fragment = this.actTierTemplateTarget.content.cloneNode(true)
        fragment.querySelectorAll("input[name]").forEach(input => {
            input.name = input.name.replace("__INDEX__", index)
        })
        fragment.querySelector("input[name$='[acts]']").value = nextActs

        this.actTiersListTarget.appendChild(fragment)
        this.focusLastInput(this.actTiersListTarget)
    }

    removeActTier(event) {
        event.preventDefault()
        event.target.closest('[data-payout-calculation-amounts-target="actTierRow"]')?.remove()
    }

    // ---- helpers ------------------------------------------------------------

    checkedValue(name) {
        const checked = this.element.querySelector(`input[name="${name}"]:checked`)
        return checked ? checked.value : null
    }

    focusLastInput(list) {
        const inputs = list.querySelectorAll("input[type='number']")
        const last = inputs[inputs.length - 1]
        if (last) last.focus()
    }

    ordinalize(number) {
        const rest = number % 100
        if (rest >= 11 && rest <= 13) return `${number}th`
        switch (number % 10) {
            case 1: return `${number}st`
            case 2: return `${number}nd`
            case 3: return `${number}rd`
            default: return `${number}th`
        }
    }
}
