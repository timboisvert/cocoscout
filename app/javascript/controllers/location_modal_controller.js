import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "locationSelect", "form"]

    connect() {
        // Add escape key listener
        this.escapeListener = (e) => {
            if (e.key === "Escape") {
                this.closeModal()
            }
        }
    }

    disconnect() {
        // Remove escape key listener
        document.removeEventListener("keydown", this.escapeListener)
    }

    openModal(event) {
        event.preventDefault()
        this.modalTarget.classList.remove("hidden")
        document.addEventListener("keydown", this.escapeListener)
    }

    closeModal(event) {
        if (event) {
            event.preventDefault()
        }
        this.modalTarget.classList.add("hidden")
        document.removeEventListener("keydown", this.escapeListener)
        // Reset the form
        this.formTarget.reset()
    }

    async submitForm(event) {
        event.preventDefault()

        const formData = new FormData(this.formTarget)
        const url = this.formTarget.action

        try {
            const response = await fetch(url, {
                method: "POST",
                body: formData,
                headers: {
                    "Accept": "application/json"
                }
            })

            if (response.ok) {
                const data = await response.json()

                // Add the new location to the select dropdown
                const option = document.createElement("option")
                option.value = data.id
                option.textContent = data.name
                option.selected = true

                // Add before the last option (if there's an "Add a Location" option)
                this.locationSelectTarget.appendChild(option)

                // Trigger change event
                this.locationSelectTarget.dispatchEvent(new Event("change", { bubbles: true }))

                // Close modal
                this.closeModal()
            } else {
                // Handle validation errors - show them in the modal
                const errors = await response.json()
                console.error("Form errors:", errors)
                // Optionally display errors in the modal form
            }
        } catch (error) {
            console.error("Error submitting location form:", error)
        }
    }

    handleLocationChange(event) {
        // This is just a placeholder if we need to react to location selection
    }
}

