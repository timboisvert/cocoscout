import { Controller } from "@hotwired/stimulus"

// Change email on the Account page: two steps in one modal. The new address
// goes to the server, which emails it a 6-digit code; the address goes again
// with the code, and only then does the account's email change.
export default class extends Controller {
    static targets = ["modal", "form", "emailInput", "profileCheckbox", "errorMessage",
        "addressStep", "codeStep", "codeInput", "sentTo", "lifetime", "sendButton", "changeButton"]

    open() {
        this.modalTarget.classList.remove("hidden")
        this.emailInputTarget.value = ""
        this.profileCheckboxTargets.forEach(checkbox => {
            checkbox.checked = true
        })
        this.startOver()
    }

    close() {
        this.modalTarget.classList.add("hidden")
    }

    // Back to step one: the address.
    startOver() {
        this.hideError()
        this.codeInputTarget.value = ""
        this.showStep("address")
        this.emailInputTarget.focus()
    }

    showStep(step) {
        const onCode = step === "code"
        this.addressStepTarget.classList.toggle("hidden", onCode)
        this.codeStepTarget.classList.toggle("hidden", !onCode)
        this.sendButtonTarget.classList.toggle("hidden", onCode)
        this.changeButtonTarget.classList.toggle("hidden", !onCode)
        this.onCodeStep = onCode
    }

    hideError() {
        this.errorMessageTarget.classList.add("hidden")
        this.errorMessageTarget.textContent = ""
    }

    showError(message) {
        this.errorMessageTarget.textContent = message
        this.errorMessageTarget.classList.remove("hidden")
    }

    async submit(event) {
        event.preventDefault()
        this.hideError()

        const newEmail = this.emailInputTarget.value.trim()
        if (!newEmail) {
            this.showError("Enter the new email address.")
            return
        }

        const body = {
            email_address: newEmail,
            profile_ids: this.profileCheckboxTargets.filter(cb => cb.checked).map(cb => cb.value)
        }
        if (this.onCodeStep) {
            body.code = this.codeInputTarget.value.replace(/\D/g, "")
            if (!body.code) {
                this.showError("Enter the code we emailed you.")
                return
            }
        }

        try {
            const response = await fetch("/account/email", {
                method: "PATCH",
                headers: {
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                    "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
                },
                body: JSON.stringify(body)
            })
            const data = await response.json()

            if (!data.success) {
                this.showError(data.error || "That didn't work. Please try again.")
            } else if (data.needs_code) {
                this.sentToTarget.textContent = data.email_address
                this.lifetimeTarget.textContent = data.lifetime
                this.showStep("code")
                this.codeInputTarget.focus()
            } else {
                // Reload the page to show the new email.
                window.location.reload()
            }
        } catch (error) {
            this.showError("That didn't go through. Please try again.")
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }
}
