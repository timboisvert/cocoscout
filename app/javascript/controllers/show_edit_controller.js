import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["eventTypeSelect", "sectionTitle"]

    connect() {
        this.updateTitle()
    }

    updateTitle() {
        if (!this.hasEventTypeSelectTarget || !this.hasSectionTitleTarget) return

        const eventType = this.eventTypeSelectTarget.value
        const eventTypeLabel = this.eventTypeSelectTarget.options[this.eventTypeSelectTarget.selectedIndex].text

        this.sectionTitleTarget.textContent = `Optional ${eventTypeLabel} Settings`
    }

    removePoster() {
        // Hide the poster image
        const posterImage = this.element.querySelector('.poster-image')
        if (posterImage) {
            posterImage.style.display = 'none'
        }

        // Set the hidden field to indicate poster should be removed
        const removePosterField = this.element.querySelector('.remove-poster-hidden')
        if (removePosterField) {
            removePosterField.value = '1'
        }

        // Hide the remove button
        const removeButton = this.element.querySelector('.remove-poster-btn')
        if (removeButton) {
            removeButton.style.display = 'none'
        }

        // Add a message indicating the poster will be removed
        const posterContainer = this.element.querySelector('.poster-container')
        if (posterContainer) {
            const message = document.createElement('div')
            message.className = 'mt-2 mb-4 text-sm text-pink-500 font-medium'
            message.textContent = 'Poster will be removed when you click Update Show below'
            posterContainer.parentNode.insertBefore(message, posterContainer)
        }
    }
}
