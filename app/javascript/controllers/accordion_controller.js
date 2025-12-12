import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["content", "icon"]
    static values = { expanded: Boolean }

    connect() {
        this.updateDisplay()
    }

    toggle() {
        this.expandedValue = !this.expandedValue
        this.updateDisplay()
    }

    updateDisplay() {
        if (this.hasContentTarget) {
            this.contentTarget.classList.toggle("hidden", !this.expandedValue)
        }

        if (this.hasIconTarget) {
            this.iconTarget.classList.toggle("rotate-180", this.expandedValue)
        }
    }
}
