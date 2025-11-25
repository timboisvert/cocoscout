import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["input", "counter"]
    static values = {
        max: Number
    }

    connect() {
        this.updateCounter()
    }

    updateCounter() {
        const length = this.inputTarget.value.length
        const remaining = this.maxValue - length

        this.counterTarget.textContent = `${length}/${this.maxValue}`

        // Update color based on remaining characters
        if (remaining < 0) {
            this.counterTarget.classList.remove("text-gray-500", "text-yellow-600")
            this.counterTarget.classList.add("text-pink-600", "font-semibold")
        } else if (remaining < 50) {
            this.counterTarget.classList.remove("text-gray-500", "text-pink-600")
            this.counterTarget.classList.add("text-yellow-600")
        } else {
            this.counterTarget.classList.remove("text-yellow-600", "text-pink-600", "font-semibold")
            this.counterTarget.classList.add("text-gray-500")
        }
    }
}
