import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["eventTypeSelect", "showOnlyFields", "submitButton"]

    connect() {
        this.updateUI()
    }

    updateUI() {
        if (!this.hasEventTypeSelectTarget) return

        const eventType = this.eventTypeSelectTarget.value
        const eventTypeLabel = this.eventTypeSelectTarget.options[this.eventTypeSelectTarget.selectedIndex].text

        // Show/hide show-only fields
        if (this.hasShowOnlyFieldsTarget) {
            if (eventType === "show") {
                this.showOnlyFieldsTarget.classList.remove("hidden")
                this.enableFields(this.showOnlyFieldsTarget)
            } else {
                this.showOnlyFieldsTarget.classList.add("hidden")
                this.disableFields(this.showOnlyFieldsTarget)
            }
        }

        // Update submit button text
        if (this.hasSubmitButtonTarget) {
            this.submitButtonTarget.value = `Update ${eventTypeLabel}`
        }
    }

    enableFields(container) {
        const inputs = container.querySelectorAll("input, select, textarea")
        inputs.forEach(input => {
            // Don't enable file inputs or hidden fields that should stay disabled
            if (input.type !== 'file' && input.type !== 'hidden') {
                input.disabled = false
            }
        })
    }

    disableFields(container) {
        const inputs = container.querySelectorAll("input, select, textarea")
        inputs.forEach(input => {
            // Don't disable file inputs or hidden fields
            if (input.type !== 'file' && input.type !== 'hidden') {
                input.disabled = true
            }
        })
    }
}
