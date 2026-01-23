import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["inPersonRadio", "onlineRadio", "inPersonFields", "onlineFields"]

    toggle() {
        const isOnline = this.onlineRadioTarget.checked

        if (isOnline) {
            this.inPersonFieldsTarget.classList.add("hidden")
            this.onlineFieldsTarget.classList.remove("hidden")
        } else {
            this.inPersonFieldsTarget.classList.remove("hidden")
            this.onlineFieldsTarget.classList.add("hidden")
        }
    }
}
