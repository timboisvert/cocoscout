import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="confirm-delete"
export default class extends Controller {
    static targets = ["input", "button"]

    connect() {
        this.checkMatch()
    }

    checkInput() {
        // Legacy method - checks for "DELETE"
        const value = this.inputTarget.value.trim()
        this.buttonTarget.disabled = (value !== "DELETE")
    }

    checkMatch() {
        if (!this.hasInputTarget || !this.hasButtonTarget) return

        // Check for custom expected value, otherwise use "DELETE"
        const expected = (this.inputTarget.dataset.expected || "DELETE").trim().toLowerCase()
        const value = this.inputTarget.value.trim().toLowerCase()

        if (value === expected) {
            this.buttonTarget.disabled = false
            this.buttonTarget.classList.remove("opacity-50", "cursor-not-allowed")
            this.buttonTarget.classList.add("cursor-pointer")
        } else {
            this.buttonTarget.disabled = true
            this.buttonTarget.classList.add("opacity-50", "cursor-not-allowed")
            this.buttonTarget.classList.remove("cursor-pointer")
        }
    }
}
