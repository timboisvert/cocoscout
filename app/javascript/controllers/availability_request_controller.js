import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["specificSection", "castDropdown", "viewDetailsButton", "showsSection"]

    connect() {
        // Listen to all radio button changes
        this.element.addEventListener('change', (e) => {
            if (e.target.name === 'recipient_type') {
                this.handleRecipientTypeChange(e.target.value)
            }
        })
    }

    toggleShowSelection(event) {
        const value = event.target.value
        if (value === "specific") {
            this.showsSectionTarget.classList.remove("hidden")
        } else {
            this.showsSectionTarget.classList.add("hidden")
        }
    }

    updateMessage(event) {
        // Get all checked show checkboxes
        const checkedShows = Array.from(document.querySelectorAll('input[name="show_ids[]"]:checked'))
        
        if (checkedShows.length === 0) return

        // Build the shows list for the message
        const showsList = checkedShows.map(checkbox => {
            const label = checkbox.parentElement
            // Get the event type badge text
            const eventType = label.querySelector('.inline-flex').textContent.trim()
            
            // Get the date/time span (the one with text-sm class)
            const dateSpan = label.querySelector('span.text-sm')
            
            // Get all text content and parse it
            const fullText = dateSpan.textContent.trim()
            
            // Split by " - " to separate date/time from secondary name
            const parts = fullText.split(' - ')
            const dateTimePart = parts[0].trim() // e.g., "Fri, Dec 19, 2025 at 9:00 PM"
            const secondaryName = parts.length > 1 ? parts[1].trim() : null
            
            // Split date and time by " at "
            const atIndex = dateTimePart.indexOf(' at ')
            if (atIndex === -1) {
                // Fallback if format is unexpected
                return `• ${eventType} on ${dateTimePart}`
            }
            
            const datePart = dateTimePart.substring(0, atIndex).trim()
            const timePart = dateTimePart.substring(atIndex + 4).trim()
            
            // Build the formatted string
            let formatted = `• ${eventType} on ${datePart} at ${timePart}`
            if (secondaryName) {
                formatted += ` (${secondaryName})`
            }
            return formatted
        }).join('\n')

        // Get the current message
        const messageTextarea = document.querySelector('textarea[name="message"]')
        const currentMessage = messageTextarea.value

        // Replace the shows list in the message (everything between "following upcoming" and "You can update")
        const beforeShows = currentMessage.substring(0, currentMessage.indexOf('shows & events:') + 'shows & events:'.length)
        const afterShows = currentMessage.substring(currentMessage.indexOf('\n\nYou can update'))
        
        messageTextarea.value = `${beforeShows}\n\n${showsList}${afterShows}`
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
