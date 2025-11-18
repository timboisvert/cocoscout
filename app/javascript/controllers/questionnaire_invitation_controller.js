import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["specificSection", "castDropdown", "viewDetailsButton"]

    connect() {
        // Listen to all radio button changes
        this.element.addEventListener('change', (e) => {
            if (e.target.name === 'recipient_type') {
                this.handleRecipientTypeChange(e.target.value)
            }
        })
    }

    handleRecipientTypeChange(value) {
        // Hide both sections by default
        this.specificSectionTarget.classList.add("hidden")
        if (this.hasCastDropdownTarget) {
            this.castDropdownTarget.classList.add("hidden")
        }

        // Hide the cast member status details when switching away from "all"
        const statusDiv = document.getElementById('cast-member-status')
        if (statusDiv && value !== "all") {
            statusDiv.classList.add("hidden")
        }

        // Show/hide the "View Details" button based on selection
        if (this.hasViewDetailsButtonTarget) {
            if (value === "all") {
                this.viewDetailsButtonTarget.classList.remove("hidden")
            } else {
                this.viewDetailsButtonTarget.classList.add("hidden")
            }
        }

        // Show the appropriate section based on selection
        if (value === "specific") {
            this.specificSectionTarget.classList.remove("hidden")
        } else if (value === "cast" && this.hasCastDropdownTarget) {
            this.castDropdownTarget.classList.remove("hidden")
        }
    }

    toggleSpecific(event) {
        this.handleRecipientTypeChange(event.target.value)
    }

    toggleCastDropdown(event) {
        this.handleRecipientTypeChange(event.target.value)
    }
}
