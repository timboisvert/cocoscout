import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["eventStartRadio", "afterEventRadio", "neverRadio"]

    connect() {
        this.updateStyles()
    }

    updateStyles() {
        const radios = this.element.querySelectorAll('input[type="radio"]')
        radios.forEach(radio => {
            const container = radio.closest('.border-2')
            if (container) {
                if (radio.checked) {
                    container.classList.remove('border-gray-200', 'hover:border-gray-300', 'bg-white')
                    container.classList.add('border-pink-500', 'bg-pink-50')
                } else {
                    container.classList.remove('border-pink-500', 'bg-pink-50')
                    container.classList.add('border-gray-200', 'hover:border-gray-300', 'bg-white')
                }
            }
        })
    }
}
