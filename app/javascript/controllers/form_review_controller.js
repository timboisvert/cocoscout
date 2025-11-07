import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["checkbox", "submitButton"]

    connect() {
        // Hide button by default if checkbox is unchecked
        this.updateButtonVisibility()
    }

    toggleSubmitButton() {
        this.updateButtonVisibility()
    }

    updateButtonVisibility() {
        if (this.checkboxTarget.checked) {
            this.submitButtonTarget.style.display = "inline-block"
        } else {
            this.submitButtonTarget.style.display = "none"
        }
    }
}
