import { Controller } from "@hotwired/stimulus"

// Auto-opens a modal controller on page load
// Usage: data-controller="auto-modal" data-auto-modal-target-value="attendance-modal"
export default class extends Controller {
    static values = {
        target: String  // The data-controller name to find and open
    }

    connect() {
        // Use setTimeout to ensure the target controller is fully initialized
        setTimeout(() => {
            this.openTargetModal()
        }, 100)
    }

    openTargetModal() {
        // Find the element with the target controller
        const targetElement = this.element.querySelector(`[data-controller*="${this.targetValue}"]`)
        if (targetElement) {
            // Get the Stimulus controller instance and call openModal
            const controller = this.application.getControllerForElementAndIdentifier(
                targetElement,
                this.targetValue
            )
            if (controller && typeof controller.openModal === "function") {
                controller.openModal()
            }
        }
    }
}
