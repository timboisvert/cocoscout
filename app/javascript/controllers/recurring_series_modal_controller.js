import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["durationSelect", "customDateField"]

    close() {
        const frame = document.getElementById('recurring_series_modal')
        if (frame) {
            frame.innerHTML = ''
        }
    }

    closeOnBackdrop(event) {
        if (event.target === this.element) {
            this.close()
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    toggleCustomDate() {
        if (!this.hasDurationSelectTarget || !this.hasCustomDateFieldTarget) return

        const isCustom = this.durationSelectTarget.value === 'custom'
        this.customDateFieldTarget.classList.toggle('hidden', !isCustom)
    }
}
