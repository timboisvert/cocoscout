import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="confirm-archive"
export default class extends Controller {
    static targets = ["confirmCheckbox", "submitButton", "hiddenField"]

    connect() {
        this.toggle()
    }

    toggle() {
        if (!this.hasConfirmCheckboxTarget) return

        const checked = this.confirmCheckboxTarget.checked

        if (this.hasSubmitButtonTarget) {
            this.submitButtonTarget.disabled = !checked
            this.submitButtonTarget.classList.toggle("opacity-50", !checked)
            this.submitButtonTarget.classList.toggle("cursor-not-allowed", !checked)
        }

        if (this.hasHiddenFieldTarget) {
            this.hiddenFieldTarget.value = checked ? "1" : "0"
        }
    }
}
