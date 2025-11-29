import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="confirm-delete"
export default class extends Controller {
    static targets = ["input", "button"]

    checkInput() {
        const value = this.inputTarget.value.trim()
        this.buttonTarget.disabled = (value !== "DELETE")
    }
}
