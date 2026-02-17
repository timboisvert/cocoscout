import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modeInput", "windowFields"]

    selectMode(event) {
        const label = event.currentTarget
        const mode = label.dataset.preRegistrationMode

        // Update radio button selection
        this.modeInputTargets.forEach(input => {
            input.checked = input.value === mode
        })

        // Update visual styling on all labels
        this.element.querySelectorAll('[data-pre-registration-mode]').forEach(el => {
            if (el.dataset.preRegistrationMode === mode) {
                el.classList.add('border-pink-500', 'bg-pink-50')
                el.classList.remove('border-gray-200', 'hover:border-gray-300', 'bg-white')
            } else {
                el.classList.remove('border-pink-500', 'bg-pink-50')
                el.classList.add('border-gray-200', 'hover:border-gray-300', 'bg-white')
            }
        })

        // Show/hide window fields based on mode
        if (this.hasWindowFieldsTarget) {
            if (mode === 'disabled') {
                this.windowFieldsTarget.classList.add('hidden')
            } else {
                this.windowFieldsTarget.classList.remove('hidden')
            }
        }
    }
}
