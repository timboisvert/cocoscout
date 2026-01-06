import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["toggle", "options"]

    toggle() {
        if (this.hasOptionsTarget && this.hasToggleTarget) {
            if (this.toggleTarget.checked) {
                this.optionsTarget.classList.remove("hidden")
            } else {
                this.optionsTarget.classList.add("hidden")
            }
        }
    }
}
