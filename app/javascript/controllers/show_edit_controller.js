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

    removePoster() {
        // Hide the poster image
        const posterImage = this.element.querySelector('.poster-image')
        if (posterImage) {
            posterImage.style.display = 'none'
        }

        // Set the hidden field to indicate poster should be removed
        const removePosterField = this.element.querySelector('.remove-poster-hidden')
        if (removePosterField) {
            removePosterField.value = '1'
        }

        // Hide the remove button
        const removeButton = this.element.querySelector('.remove-poster-btn')
        if (removeButton) {
            removeButton.style.display = 'none'
        }

        // Add a message indicating the poster will be removed
        const posterContainer = this.element.querySelector('.poster-container')
        if (posterContainer) {
            const message = document.createElement('div')
            message.className = 'mt-2 mb-4 text-sm text-pink-500 font-medium'
            message.textContent = 'Poster will be removed when you click Update Show below'
            posterContainer.parentNode.insertBefore(message, posterContainer)
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
