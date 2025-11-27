import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["input", "checkButton", "updateButton", "message", "form"]
    static values = {
        checkUrl: String
    }

    connect() {
        this.updateButtonTarget.style.display = 'none'
        this.messageTarget.classList.add('hidden')
    }

    inputChanged() {
        // Reset state when input changes
        this.updateButtonTarget.style.display = 'none'
        this.checkButtonTarget.classList.remove('hidden')
        this.messageTarget.classList.add('hidden')
        this.checkButtonTarget.disabled = false
    }

    preventEnterSubmit(event) {
        if (event.key === 'Enter') {
            event.preventDefault()
            // If update button is visible, submit the form
            if (!this.updateButtonTarget.classList.contains('hidden')) {
                this.formTarget.requestSubmit()
            } else {
                // Otherwise, trigger check availability
                this.checkAvailability(event)
            }
        }
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
                this.updateButtonTarget.style.display = 'inline-flex'
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

    submitForm(event) {
        event.preventDefault()
        this.formTarget.requestSubmit()
    }
}
