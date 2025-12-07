import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = {
        debounce: { type: Number, default: 0 }
    }

    connect() {
        this.timeout = null
        this.submitting = false
    }

    submit() {
        // Prevent double submissions
        if (this.submitting) return

        if (this.debounceValue > 0) {
            clearTimeout(this.timeout)
            this.timeout = setTimeout(() => {
                this.performSubmit()
            }, this.debounceValue)
        } else {
            this.performSubmit()
        }
    }

    performSubmit() {
        if (this.submitting) return
        this.submitting = true

        this.element.requestSubmit()

        // Reset after a short delay to allow for turbo stream response
        setTimeout(() => {
            this.submitting = false
        }, 500)
    }
}
