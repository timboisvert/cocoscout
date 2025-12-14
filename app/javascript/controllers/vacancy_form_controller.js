import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["assignmentRow", "assignmentInput", "indicator", "checkmark"]

    connect() {
        this.updateVisualState()
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
