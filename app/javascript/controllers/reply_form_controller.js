import { Controller } from "@hotwired/stimulus"

// Handles inline reply forms for messages
export default class extends Controller {
    static targets = ["form", "body"]
    static values = { parentId: Number }

    connect() {
        // Hide form initially
        if (this.hasFormTarget) {
            this.formTarget.classList.add("hidden")
        }
    }

    toggle(event) {
        event.preventDefault()

        if (this.hasFormTarget) {
            const isHidden = this.formTarget.classList.contains("hidden")

            if (isHidden) {
                this.formTarget.classList.remove("hidden")
                // Focus the textarea/input
                const textarea = this.formTarget.querySelector("trix-editor, textarea, input[type='text']")
                if (textarea) {
                    setTimeout(() => textarea.focus(), 50)
                }
            } else {
                this.formTarget.classList.add("hidden")
            }
        }
    }

    cancel(event) {
        event.preventDefault()
        if (this.hasFormTarget) {
            this.formTarget.classList.add("hidden")
        }
    }

    // Called when user types in the reply form - dispatches event for parent controller
    typing() {
        this.dispatch("typing", { bubbles: true })
    }

    // Called after successful form submission
    submitted() {
        if (this.hasFormTarget) {
            this.formTarget.classList.add("hidden")
        }
        // Clear the form body if it exists
        if (this.hasBodyTarget) {
            this.bodyTarget.value = ""
        }
    }
}
