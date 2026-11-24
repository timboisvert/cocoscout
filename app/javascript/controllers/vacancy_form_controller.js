import { Controller } from "@hotwired/stimulus"

// The Can't Make It page (vacancy/show). One choice among radio rows, as
// always; or, for someone with several acts in an act-based show, a ticked
// box per act: unticking one keeps that act, and the pink button counts
// what is left ticked.
export default class extends Controller {
    static targets = ["assignmentRow", "assignmentInput", "indicator", "checkmark", "actRow", "submit"]
    static values = { unit: { type: String, default: "act" }, units: { type: String, default: "acts" } }

    connect() {
        this.updateVisualState()
        this.refresh()
    }

    // The ticked boxes: a kept act's row goes white and says so, and the
    // button names how many are left, greyed out when none is.
    refresh() {
        if (!this.hasActRowTarget) return

        let ticked = 0
        this.actRowTargets.forEach((row) => {
            const on = row.querySelector('input[type="checkbox"]').checked
            if (on) ticked += 1
            row.classList.toggle("bg-pink-50", on)
            row.querySelector("[data-held-by]")?.classList.toggle("hidden", !on)
            row.querySelector("[data-kept]")?.classList.toggle("hidden", on)
        })

        if (!this.hasSubmitTarget) return
        const words = ticked === 0 ? `Choose at least one ${this.unitValue}`
            : ticked === 1 ? `I confirm that I can't make this ${this.unitValue}`
                : `I confirm that I can't make these ${ticked} ${this.unitsValue}`
        this.submitTarget.disabled = ticked === 0
        const label = this.submitTarget.querySelector("span") || this.submitTarget
        label.textContent = words
    }

    selectAssignment(event) {
        // Find the radio input in the clicked row
        const row = event.currentTarget
        const input = row.querySelector('input[type="radio"]')

        if (input) {
            input.checked = true
            this.updateVisualState()
        }
    }

    updateVisualState() {
        this.assignmentRowTargets.forEach((row, index) => {
            const input = row.querySelector('input[type="radio"]')
            const indicator = row.querySelector('[data-vacancy-form-target="indicator"]')
            const checkmark = row.querySelector('[data-vacancy-form-target="checkmark"]')

            if (input && indicator && checkmark) {
                if (input.checked) {
                    indicator.classList.remove('border-gray-300')
                    indicator.classList.add('border-pink-500', 'bg-pink-500')
                    checkmark.classList.remove('hidden')
                } else {
                    indicator.classList.remove('border-pink-500', 'bg-pink-500')
                    indicator.classList.add('border-gray-300')
                    checkmark.classList.add('hidden')
                }
            }
        })
    }
}
