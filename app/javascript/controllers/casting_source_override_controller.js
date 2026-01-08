import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["toggle", "options", "clearField"]

    toggle() {
        const isEnabled = this.toggleTarget.checked

        if (isEnabled) {
            this.optionsTarget.classList.remove("hidden")
            this.clearFieldTarget.value = "0"
        } else {
            this.optionsTarget.classList.add("hidden")
            this.clearFieldTarget.value = "1"
        }
    }
}
