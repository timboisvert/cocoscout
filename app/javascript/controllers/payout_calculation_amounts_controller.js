import { Controller } from "@hotwired/stimulus"

// The amounts for one payout approach (manage/payout_calculation_wizard/_amounts_fields).
// Reveals the optional panels (guaranteed minimum, shares, the two per-act
// shapes, the role-holder all-in figure or table) and manages the per-act
// tables: rows of "N acts → $X" that number themselves one past the last row
// when added — the main act table and the role holder's own table are the
// same shape, told apart by data-list="act" | "roleActs" — and rows of
// "show role → $X" (MC $100, Stage Kitten $35).
export default class extends Controller {
    static targets = [
        "minimumPanel",
        "sharesPanel",
        "perActSimple", "perActTiers",
        "actTiersList", "actTierRow", "actTierActs", "actTierLabel", "actTierTemplate",
        "roleActTiersList", "roleActTierTemplate",
        "roleStackingFlat", "roleStackingTable",
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

    // Which all-in panel a role holder who also performs needs: the set
    // amount, their own table, or neither.
    updateRoleStacking() {
        const stacking = this.checkedValue("distribution[role_stacking]") || "both"
        if (this.hasRoleStackingFlatTarget) this.roleStackingFlatTarget.classList.toggle("hidden", stacking !== "flat")
        if (this.hasRoleStackingTableTarget) this.roleStackingTableTarget.classList.toggle("hidden", stacking !== "table")
    }

    // Add another "N acts → $X" row, one act past the last row — to the main
    // act table or the role holder's, whichever the button's data-list names.
    addActTier(event) {
        if (event) event.preventDefault()
        const which = event?.currentTarget?.dataset?.list === "roleActs" ? "roleActs" : "act"
        const list = which === "roleActs" ? (this.hasRoleActTiersListTarget && this.roleActTiersListTarget) : (this.hasActTiersListTarget && this.actTiersListTarget)
        const template = which === "roleActs" ? (this.hasRoleActTierTemplateTarget && this.roleActTierTemplateTarget) : (this.hasActTierTemplateTarget && this.actTierTemplateTarget)
        if (!list || !template) return

        const index = this.actTierIndex++
        const rows = list.querySelectorAll('[data-payout-calculation-amounts-target="actTierRow"]')
        const lastRow = rows[rows.length - 1]
        const nextActs = lastRow ? (parseInt(lastRow.querySelector("input[name$='[acts]']").value, 10) || 0) + 1 : 1

        const fragment = template.content.cloneNode(true)
        fragment.querySelectorAll("input[name]").forEach(input => {
            input.name = input.name.replace("__INDEX__", index)
        })
        fragment.querySelector("input[name$='[acts]']").value = nextActs

        list.appendChild(fragment)
        this.relabelActTiers()
        this.focusLastInput(list)
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
