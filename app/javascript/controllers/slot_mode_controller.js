import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["numbered", "timeBased", "named", "openList", "openListCapacity"]

    connect() {
        // On initial load, disable inputs in hidden sections
        this.initializeSections()
    }

    initializeSections() {
        // Find which mode is currently selected
        const selectedRadio = this.element.querySelector('input[name="slot_generation_mode"]:checked')
        const currentMode = selectedRadio ? selectedRadio.value : null

        // Disable inputs in hidden sections to prevent form submission conflicts
        this.updateSection(this.numberedTarget, currentMode === 'numbered')
        this.updateSection(this.timeBasedTarget, currentMode === 'time_based')
        this.updateSection(this.namedTarget, currentMode === 'named')
        this.updateSection(this.openListTarget, currentMode === 'open_list')
    }

    updateSection(section, isActive) {
        if (!section) return

        section.classList.toggle("hidden", !isActive)

        // Disable/enable all form inputs in this section
        const inputs = section.querySelectorAll('input, textarea, select')
        inputs.forEach(input => {
            // Don't disable the openListCapacity field here - that's handled by toggleOpenListLimit
            if (this.hasOpenListCapacityTarget && input === this.openListCapacityTarget) return
            input.disabled = !isActive
        })
    }

    toggle(event) {
        const value = event.target.value

        // Update all sections - show/hide and enable/disable inputs
        this.updateSection(this.numberedTarget, value === 'numbered')
        this.updateSection(this.timeBasedTarget, value === 'time_based')
        this.updateSection(this.namedTarget, value === 'named')
        this.updateSection(this.openListTarget, value === 'open_list')

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
