import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["input", "checkButton", "updateButton", "message", "form"]
    static values = {
        checkUrl: String
    }

    connect() {
        this.updateButtonTarget.classList.add('hidden')
        this.messageTarget.classList.add('hidden')
    }

    inputChanged() {
        // Reset state when input changes
        this.updateButtonTarget.classList.add('hidden')
        this.checkButtonTarget.classList.remove('hidden')
        this.messageTarget.classList.add('hidden')
        this.checkButtonTarget.disabled = false
    }

    async checkAvailability(event) {
        event.preventDefault()

        const proposedKey = this.inputTarget.value.trim()

        if (!proposedKey) {
            this.showMessage("Please enter a URL", "error")
            return
        }

        this.checkButtonTarget.disabled = true
        this.checkButtonTarget.textContent = "Checking..."

        try {
            const response = await fetch(this.checkUrlValue, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
                },
                body: JSON.stringify({ public_key: proposedKey })
            })

            const data = await response.json()

            if (data.available) {
                this.showMessage(data.message, "success")
                this.checkButtonTarget.classList.add('hidden')
                this.updateButtonTarget.classList.remove('hidden')
            } else {
                this.showMessage(data.message, "error")
                this.checkButtonTarget.disabled = false
                this.checkButtonTarget.textContent = "Check Availability"
            }
        } catch (error) {
            this.showMessage("An error occurred. Please try again.", "error")
            this.checkButtonTarget.disabled = false
            this.checkButtonTarget.textContent = "Check Availability"
        }
    }

    showMessage(text, type) {
        this.messageTarget.classList.remove('hidden', 'text-green-700', 'bg-green-50', 'border-green-200', 'text-pink-700', 'bg-pink-50', 'border-pink-200')

        if (type === "success") {
            this.messageTarget.classList.add('text-green-700', 'bg-green-50', 'border-green-200')
        } else {
            this.messageTarget.classList.add('text-pink-700', 'bg-pink-50', 'border-pink-200')
        }

        this.messageTarget.textContent = text
        this.messageTarget.classList.remove('hidden')
    }
}
