import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "locationSelect", "form", "errorContainer", "errorCount", "errorList", "inPersonContainer", "onlineContainer", "isOnlineField", "toggleLink", "toggleLinkText"]
    static values = { eventType: String }

    connect() {
        // Add escape key listener
        this.escapeListener = (e) => {
            if (e.key === "Escape") {
                this.closeModal()
            }
        }

        // Initialize location type visibility based on current selection
        this.initializeLocationType()
    }

    initializeLocationType() {
        // Check if we have the necessary targets
        if (!this.hasIsOnlineFieldTarget || !this.hasInPersonContainerTarget) {
            return
        }

        // Show/hide based on the hidden field value
        if (this.isOnlineFieldTarget.value === "true" || this.isOnlineFieldTarget.value === "1") {
            this.showOnlineFields()
        } else {
            this.showInPersonFields()
        }
    }

    toggleLocationType(event) {
        event.preventDefault()

        // Toggle the hidden field value
        const currentValue = this.isOnlineFieldTarget.value === "true" || this.isOnlineFieldTarget.value === "1"

        if (currentValue) {
            // Currently online, switch to in-person
            this.isOnlineFieldTarget.value = "false"
            this.showInPersonFields()
        } else {
            // Currently in-person, switch to online
            this.isOnlineFieldTarget.value = "true"
            this.showOnlineFields()
        }
    }

    showInPersonFields() {
        if (this.hasInPersonContainerTarget) {
            this.inPersonContainerTarget.classList.remove("hidden")
        }
        if (this.hasOnlineContainerTarget) {
            this.onlineContainerTarget.classList.add("hidden")
        }
        // Update link text
        if (this.hasToggleLinkTextTarget) {
            const eventType = this.eventTypeValue || "event"
            this.toggleLinkTextTarget.textContent = `Host ${eventType} online`
        }
    }

    showOnlineFields() {
        if (this.hasInPersonContainerTarget) {
            this.inPersonContainerTarget.classList.add("hidden")
        }
        if (this.hasOnlineContainerTarget) {
            this.onlineContainerTarget.classList.remove("hidden")
        }
        // Update link text
        if (this.hasToggleLinkTextTarget) {
            const eventType = this.eventTypeValue || "event"
            this.toggleLinkTextTarget.textContent = `Host ${eventType} in person`
        }
    }

    // Called when event type changes to update the link text
    updateEventType(event) {
        this.eventTypeValue = event.target.options[event.target.selectedIndex].text.toLowerCase()
        // Re-render the current state to update link text
        if (this.isOnlineFieldTarget.value === "true" || this.isOnlineFieldTarget.value === "1") {
            this.showOnlineFields()
        } else {
            this.showInPersonFields()
        }
    }

    disconnect() {
        // Remove escape key listener
        document.removeEventListener("keydown", this.escapeListener)
    }

    openModal(event) {
        event.preventDefault()
        // Store original label text before clearing
        this.storeOriginalLabels()
        this.clearErrors()
        this.modalTarget.classList.remove("hidden")
        document.addEventListener("keydown", this.escapeListener)
    }

    storeOriginalLabels() {
        const labels = this.formTarget.querySelectorAll("label")
        labels.forEach(label => {
            if (!label.hasAttribute("data-original-text")) {
                label.setAttribute("data-original-text", label.textContent)
            }
        })
    }

    closeModal(event) {
        if (event) {
            event.preventDefault()
        }
        this.modalTarget.classList.add("hidden")
        document.removeEventListener("keydown", this.escapeListener)
        // Reset the form
        this.formTarget.reset()
        this.clearErrors()
    }

    clearErrors() {
        this.errorContainerTarget.classList.add("hidden")
        this.errorListTarget.innerHTML = ""
        this.errorCountTarget.textContent = ""
        this.clearFieldErrors()
    }

    displayErrors(errors) {
        // Clear previous error states
        this.clearFieldErrors()

        // Update field labels to show error messages
        Object.keys(errors).forEach(field => {
            const label = this.formTarget.querySelector(`label[for="location_${field}"]`)
            const input = this.formTarget.querySelector(`[name="location[${field}]"]`)

            if (label && input) {
                const fieldName = this.formatFieldName(field)
                const message = this.formatMessage(field)
                label.textContent = `${fieldName} ${message}`
                label.classList.add("text-pink-600")
                input.classList.remove("border-gray-400")
                input.classList.add("border-pink-500")
            }
        })
    }

    clearFieldErrors() {
        // Reset all field labels and borders
        const inputs = this.formTarget.querySelectorAll("input, select, textarea")
        inputs.forEach(input => {
            const fieldName = input.name.match(/location\[(.+?)\]/)?.[1]
            if (fieldName) {
                const label = this.formTarget.querySelector(`label[for="location_${fieldName}"]`)
                if (label) {
                    label.classList.remove("text-pink-600")
                    // Restore original label text
                    const originalText = label.getAttribute("data-original-text")
                    if (originalText) {
                        label.textContent = originalText
                    }
                }
            }
            input.classList.remove("border-pink-500")
            input.classList.add("border-gray-400")
        })
    }

    formatFieldName(field) {
        const names = {
            "name": "Name",
            "address1": "Street Address Line 1",
            "address2": "Street Address Line 2",
            "city": "City",
            "state": "State/Province",
            "postal_code": "Zip/Postal Code",
            "notes": "Notes"
        }
        return names[field] || field.charAt(0).toUpperCase() + field.slice(1)
    }

    formatMessage(field) {
        const messages = {
            "name": "is required",
            "address1": "is required",
            "address2": "is required",
            "city": "is required",
            "state": "is required",
            "postal_code": "is required",
            "notes": "is required"
        }
        return messages[field] || "is invalid"
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
                const data = await response.json()
                if (data.errors) {
                    this.displayErrors(data.errors)
                } else {
                    console.error("Form errors:", data)
                }
            }
        } catch (error) {
            console.error("Error submitting location form:", error)
        }
    }

    handleLocationChange(event) {
        // This is just a placeholder if we need to react to location selection
    }
}

