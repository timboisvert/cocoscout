import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "form", "emailInput", "profileCheckbox", "errorMessage", "successMessage"]

    open() {
        this.modalTarget.classList.remove("hidden")
        this.emailInputTarget.value = ""
        this.hideMessages()
        this.profileCheckboxTargets.forEach(checkbox => {
            checkbox.checked = true
        })
    }

    close() {
        this.modalTarget.classList.add("hidden")
    }

    hideMessages() {
        if (this.hasErrorMessageTarget) {
            this.errorMessageTarget.classList.add("hidden")
            this.errorMessageTarget.textContent = ""
        }
        if (this.hasSuccessMessageTarget) {
            this.successMessageTarget.classList.add("hidden")
        }
    }

    showError(message) {
        if (this.hasErrorMessageTarget) {
            this.errorMessageTarget.textContent = message
            this.errorMessageTarget.classList.remove("hidden")
        }
    }

    async submit(event) {
        event.preventDefault()
        this.hideMessages()

        const newEmail = this.emailInputTarget.value.trim()
        if (!newEmail) {
            this.showError("Please enter an email address.")
            return
        }

        // Get selected profile IDs
        const profileIds = this.profileCheckboxTargets
            .filter(cb => cb.checked)
            .map(cb => cb.value)

        try {
            const response = await fetch("/account/email", {
                method: "PATCH",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
                },
                body: JSON.stringify({
                    email_address: newEmail,
                    profile_ids: profileIds
                })
            })

            const data = await response.json()

            if (data.success) {
                // Reload the page to show updated email
                window.location.reload()
            } else {
                this.showError(data.error || "Failed to update email.")
            }
        } catch (error) {
            this.showError("An error occurred. Please try again.")
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }
}
