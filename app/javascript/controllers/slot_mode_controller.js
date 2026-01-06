import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["numbered", "timeBased", "named", "openList", "openListCapacity"]

    toggle(event) {
        const value = event.target.value

        // Hide all mode option panels
        if (this.hasNumberedTarget) this.numberedTarget.classList.add("hidden")
        if (this.hasTimeBasedTarget) this.timeBasedTarget.classList.add("hidden")
        if (this.hasNamedTarget) this.namedTarget.classList.add("hidden")
        if (this.hasOpenListTarget) this.openListTarget.classList.add("hidden")

        // Show the selected mode's options
        switch (value) {
            case 'numbered':
                if (this.hasNumberedTarget) this.numberedTarget.classList.remove("hidden")
                break
            case 'time_based':
                if (this.hasTimeBasedTarget) this.timeBasedTarget.classList.remove("hidden")
                break
            case 'named':
                if (this.hasNamedTarget) this.namedTarget.classList.remove("hidden")
                break
            case 'open_list':
                if (this.hasOpenListTarget) this.openListTarget.classList.remove("hidden")
                break
        }

        // Update visual selection state on all cards
        this.element.querySelectorAll('input[name="slot_generation_mode"]').forEach(radio => {
            const wrapper = radio.closest('.border-2')
            if (wrapper) {
                if (radio.checked) {
                    wrapper.classList.add('border-pink-500', 'bg-pink-50')
                    wrapper.classList.remove('border-gray-200')
                } else {
                    wrapper.classList.remove('border-pink-500', 'bg-pink-50')
                    wrapper.classList.add('border-gray-200')
                }
            }
        })
    }

    toggleOpenListLimit(event) {
        const isUnlimited = event.target.value === 'unlimited'
        if (this.hasOpenListCapacityTarget) {
            if (isUnlimited) {
                this.openListCapacityTarget.classList.add('opacity-50')
                this.openListCapacityTarget.disabled = true
            } else {
                this.openListCapacityTarget.classList.remove('opacity-50')
                this.openListCapacityTarget.disabled = false
            }
        }
    }
}
