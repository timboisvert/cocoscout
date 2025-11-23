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

        // For checkboxes and selects, save immediately
        if (event.target.type === 'checkbox' || event.target.type === 'select-one') {
            this.performSave()
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
        this.element.requestSubmit()

        // Reset the saving flag after a short delay
        setTimeout(() => {
            this.isSaving = false
        }, 500)
    }
}
