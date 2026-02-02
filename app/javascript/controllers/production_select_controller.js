import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="production-select"
// Handles the production dropdown selection and enables/disables the send button
export default class extends Controller {
    static targets = ["select", "button"]

    connect() {
        // Enable/disable button based on selection
        this.selectTarget.addEventListener("change", () => this.updateButton())
    }

    updateButton() {
        const hasSelection = this.selectTarget.value !== ""
        this.buttonTarget.disabled = !hasSelection
    }

    openModal(event) {
        const productionId = this.selectTarget.value
        const selectedOption = this.selectTarget.options[this.selectTarget.selectedIndex]
        const productionName = selectedOption.dataset.name

        if (!productionId) return

        // Find the contact-production controller on the page and trigger open
        const contactProductionElement = document.querySelector('[data-controller*="contact-production"]')
        if (contactProductionElement) {
            // Dispatch a custom event that contact-production will handle
            const openEvent = new CustomEvent("contact-production:open", {
                detail: {
                    productionId,
                    productionName
                },
                bubbles: true
            })
            contactProductionElement.dispatchEvent(openEvent)
        }
    }
}
