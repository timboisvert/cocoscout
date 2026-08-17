import { Controller } from "@hotwired/stimulus"

// "Before performers are paid" step of the payout calculation wizard: keeps
// the "performers share the other N%" line live as the house percentage and
// individual cuts change, and manages the repeatable "someone gets a cut" rows.
export default class extends Controller {
    static targets = ["housePercentage", "performerPercentage", "cutsList", "cutRow", "cutTemplate", "cutPercentage"]

    connect() {
        this.cutIndex = this.cutRowTargets.length
        this.updatePercentages()
    }

    updatePercentages() {
        if (!this.hasPerformerPercentageTarget) return
        const house = this.hasHousePercentageTarget ? parseFloat(this.housePercentageTarget.value) || 0 : 0
        const cuts = this.cutPercentageTargets.reduce((sum, input) => sum + (parseFloat(input.value) || 0), 0)
        const performers = Math.max(0, Math.round((100 - house - cuts) * 100) / 100)
        this.performerPercentageTarget.textContent = `${performers}%`
    }

    addCut(event) {
        if (event) event.preventDefault()
        if (!this.hasCutsListTarget || !this.hasCutTemplateTarget) return

        const index = this.cutIndex++
        const fragment = this.cutTemplateTarget.content.cloneNode(true)
        fragment.querySelectorAll("[name]").forEach(field => {
            field.name = field.name.replace("__INDEX__", index)
        })
        this.cutsListTarget.appendChild(fragment)
        this.updatePercentages()

        const select = this.cutsListTarget.querySelector('[data-payout-calculation-before-target="cutRow"]:last-child select')
        if (select) select.focus()
    }

    removeCut(event) {
        event.preventDefault()
        event.target.closest('[data-payout-calculation-before-target="cutRow"]')?.remove()
        this.updatePercentages()
    }
}
