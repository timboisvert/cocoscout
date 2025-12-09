import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="select-all"
export default class extends Controller {
    static targets = ["checkbox", "toggleButton"]

    toggleAll() {
        const enabledCheckboxes = this.checkboxTargets.filter(cb => !cb.disabled)
        const allChecked = enabledCheckboxes.every(cb => cb.checked)

        enabledCheckboxes.forEach(checkbox => {
            checkbox.checked = !allChecked
        })

        this.updateButtonText()
    }

    updateButtonText() {
        const enabledCheckboxes = this.checkboxTargets.filter(cb => !cb.disabled)
        const allChecked = enabledCheckboxes.every(cb => cb.checked)

        if (this.hasToggleButtonTarget) {
            this.toggleButtonTarget.textContent = allChecked ? "Deselect all" : "Select all"
        }
    }
}
