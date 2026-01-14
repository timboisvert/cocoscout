import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["methodRadio", "section"]

    connect() {
        this.updateVisibility()
    }

    updateVisibility() {
        const selectedRadio = this.methodRadioTargets.find(radio => radio.checked)
        if (!selectedRadio) return

        const selectedMethod = selectedRadio.value

        this.sectionTargets.forEach(section => {
            const sectionMethod = section.dataset.method
            if (sectionMethod === selectedMethod) {
                section.classList.remove('hidden')
            } else {
                section.classList.add('hidden')
            }
        })
    }
}
