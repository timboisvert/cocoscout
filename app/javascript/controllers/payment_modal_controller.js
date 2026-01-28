import { Controller } from "@hotwired/stimulus"

// Controls the payment modal for marking payments received
export default class extends Controller {
    static targets = ["modal"]

    open() {
        if (this.hasModalTarget) {
            this.modalTarget.classList.remove("hidden")
            document.body.classList.add("overflow-hidden")
        }
    }

    close() {
        if (this.hasModalTarget) {
            this.modalTarget.classList.add("hidden")
            document.body.classList.remove("overflow-hidden")
        }
    }
}
