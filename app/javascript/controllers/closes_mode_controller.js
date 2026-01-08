import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["neverRadio", "customRadio", "customFields", "modeField"]

    selectNever(event) {
        this.neverRadioTarget.checked = true
        if (this.hasModeFieldTarget) {
            this.modeFieldTarget.value = "never"
        }
        this.updateStyles()
    }

    selectCustom(event) {
        this.customRadioTarget.checked = true
        if (this.hasModeFieldTarget) {
            this.modeFieldTarget.value = "custom"
        }
        this.updateStyles()
    }

    updateStyles() {
        const options = this.element.querySelectorAll('[data-action*="closes-mode"]')
        options.forEach(option => {
            const radio = option.querySelector('input[type="radio"]')
            if (radio && radio.checked) {
                option.classList.remove('border-gray-200', 'hover:border-gray-300')
                option.classList.add('border-pink-500', 'bg-pink-50')
            } else {
                option.classList.remove('border-pink-500', 'bg-pink-50')
                option.classList.add('border-gray-200', 'hover:border-gray-300')
            }
        })
    }
}
