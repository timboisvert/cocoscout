import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="audition-schedule"
export default class extends Controller {
    static targets = ["opensAt", "closesAt", "closesAtField"]

    connect() {
        // If opens_at has a value but closes_at doesn't, set closes_at to 1 week later
        if (this.hasOpensAtTarget && this.hasClosesAtFieldTarget) {
            if (this.opensAtTarget.value && !this.closesAtTarget.value) {
                this.updateClosesAt()
            }
        }
    }

    updateClosesAt() {
        if (!this.hasOpensAtTarget || !this.hasClosesAtFieldTarget || !this.hasClosesAtTarget) return

        const opensAtValue = this.opensAtTarget.value
        if (!opensAtValue) return

        // Only update if the closes_at field is enabled (not open-ended) and empty or matches the old calculated value
        const closesAtField = this.closesAtFieldTarget
        if (closesAtField.disabled) return

        // Parse the opens_at date and add 1 week
        const opensAt = new Date(opensAtValue)
        if (isNaN(opensAt.getTime())) return

        const closesAt = new Date(opensAt.getTime() + 7 * 24 * 60 * 60 * 1000)

        // Set time to end of day (23:59)
        closesAt.setHours(23, 59, 0, 0)

        // Format for datetime-local input (YYYY-MM-DDTHH:MM)
        const formatted = closesAt.toISOString().slice(0, 16)

        // Update both the visible field and hidden field
        closesAtField.value = formatted
        this.closesAtTarget.value = formatted
    }
}
