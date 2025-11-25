import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = {
        debounceDelay: { type: Number, default: 1000 }
    }

    connect() {
        this.saveTimeout = null
        this.isSaving = false
    }

    disconnect() {
        if (this.saveTimeout) {
            clearTimeout(this.saveTimeout)
        }
    }

    save(event) {
        // Don't save while already saving
        if (this.isSaving) {
            return
        }

        // Clear any pending save
        if (this.saveTimeout) {
            clearTimeout(this.saveTimeout)
        }

        // Store the target element for later use
        this.lastTarget = event?.target || this.element

        // For checkboxes and selects, save immediately but with a tiny delay
        // to ensure any onchange handlers complete first
        const targetType = event?.target?.type;
        if (targetType === 'checkbox' || targetType === 'select-one' || targetType === 'hidden') {
            this.saveTimeout = setTimeout(() => {
                this.performSave()
            }, 100)
        } else {
            // For text inputs, debounce the save
            this.saveTimeout = setTimeout(() => {
                this.performSave()
            }, this.debounceDelayValue)
        }
    }

    performSave() {
        this.isSaving = true

        // Submit the form
        // Check if the element that triggered the save has a form attribute
        if (this.lastTarget && this.lastTarget.hasAttribute('form')) {
            const formId = this.lastTarget.getAttribute('form')
            const targetForm = document.getElementById(formId)
            if (targetForm) {
                targetForm.requestSubmit()
            } else {
                this.element.requestSubmit()
            }
        } else {
            this.element.requestSubmit()
        }

        // Reset the saving flag after a short delay
        setTimeout(() => {
            this.isSaving = false
        }, 500)
    }
}
