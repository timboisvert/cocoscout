import { Controller } from "@hotwired/stimulus"

// The amounts for one payout approach (manage/payout_calculation_wizard/_amounts_fields).
// Reveals the optional panels (guaranteed minimum, shares, the two per-act
// shapes) and manages the per-act tables: rows of "N acts → $X" that number
// themselves one past the last row when added, and rows of "show role → $X"
// (MC $100, Stage Kitten $35).
export default class extends Controller {
    static targets = [
        "minimumPanel",
        "sharesPanel",
        "perActSimple", "perActTiers",
        "actTiersList", "actTierRow", "actTierActs", "actTierLabel", "actTierTemplate",
        "roleAmountsList", "roleAmountRow", "roleAmountTemplate"
    ]

    connect() {
        this.actTierIndex = this.actTierRowTargets.length
        this.roleAmountIndex = this.roleAmountRowTargets.length
        this.relabelActTiers()
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
        const mode = this.checkedValue("distribution[act_mode]") || "simple"
        if (this.hasPerActSimpleTarget) this.perActSimpleTarget.classList.toggle("hidden", mode !== "simple")
        if (this.hasPerActTiersTarget) this.perActTiersTarget.classList.toggle("hidden", mode !== "tiers")
    }

    // Add another "N acts → $X" row, one act past the last row.
    addActTier(event) {
        if (event) event.preventDefault()
        if (!this.hasActTiersListTarget || !this.hasActTierTemplateTarget) return

        const index = this.actTierIndex++
        const lastRow = this.actTierRowTargets[this.actTierRowTargets.length - 1]
        const nextActs = lastRow ? (parseInt(lastRow.querySelector("input[name$='[acts]']").value, 10) || 0) + 1 : 1

        const fragment = this.actTierTemplateTarget.content.cloneNode(true)
        fragment.querySelectorAll("input[name]").forEach(input => {
            input.name = input.name.replace("__INDEX__", index)
        })
        fragment.querySelector("input[name$='[acts]']").value = nextActs

        this.actTiersListTarget.appendChild(fragment)
        this.relabelActTiers()
        this.focusLastInput(this.actTiersListTarget)
    }

    removeActTier(event) {
        event.preventDefault()
        event.target.closest('[data-payout-calculation-amounts-target="actTierRow"]')?.remove()
    }

    // Another "show role → $X" row.
    addRoleAmount(event) {
        if (event) event.preventDefault()
        if (!this.hasRoleAmountsListTarget || !this.hasRoleAmountTemplateTarget) return

        const index = this.roleAmountIndex++
        const fragment = this.roleAmountTemplateTarget.content.cloneNode(true)
        fragment.querySelectorAll("input[name]").forEach(input => {
            input.name = input.name.replace("__INDEX__", index)
        })
        this.roleAmountsListTarget.appendChild(fragment)

        const rows = this.roleAmountRowTargets
        const nameInput = rows[rows.length - 1]?.querySelector("input[type='text']")
        if (nameInput) nameInput.focus()
    }

    removeRoleAmount(event) {
        event.preventDefault()
        event.target.closest('[data-payout-calculation-amounts-target="roleAmountRow"]')?.remove()
    }

    // "1 act →" / "2 acts →" next to each count.
    relabelActTiers() {
        this.actTierRowTargets.forEach(row => {
            const acts = parseInt(row.querySelector("input[name$='[acts]']")?.value, 10)
            const label = row.querySelector('[data-payout-calculation-amounts-target="actTierLabel"]')
            if (label) label.textContent = `${acts === 1 ? "act" : "acts"} →`
        })
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
}
