import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["enabledToggle", "callTimeFields", "callTimeField"]

    connect() {
        // Listen for date_and_time changes to auto-set call time
        const dateTimeField = document.querySelector('input[name="show[date_and_time]"]')
        if (dateTimeField) {
            dateTimeField.addEventListener('change', this.autoSetCallTime.bind(this))
        }
    }

    toggleEnabled() {
        if (this.enabledToggleTarget.checked) {
            this.callTimeFieldsTarget.classList.remove("hidden")
            // Auto-set call time to 30 minutes before event time if not already set
            if (!this.callTimeFieldTarget.value) {
                this.autoSetCallTime()
            }
        } else {
            this.callTimeFieldsTarget.classList.add("hidden")
        }
    }

    autoSetCallTime() {
        const dateTimeField = document.querySelector('input[name="show[date_and_time]"]')
        if (!dateTimeField || !dateTimeField.value) return

        // Parse the datetime-local value
        const eventDateTime = new Date(dateTimeField.value)
        if (isNaN(eventDateTime.getTime())) return

        // Subtract 30 minutes
        const callTime = new Date(eventDateTime.getTime() - 30 * 60 * 1000)

        // Format as HH:MM for time input
        const hours = callTime.getHours().toString().padStart(2, '0')
        const minutes = callTime.getMinutes().toString().padStart(2, '0')

        this.callTimeFieldTarget.value = `${hours}:${minutes}`
    }
}
