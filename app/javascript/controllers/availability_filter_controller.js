import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["checkboxes", "eventList", "checkbox", "enableCheckbox", "eventSection", "count"]

    connect() {
        this.updateEventList()
    }

    toggleSection() {
        if (this.hasEnableCheckboxTarget && this.hasEventSectionTarget) {
            const isChecked = this.enableCheckboxTarget.checked
            if (isChecked) {
                this.eventSectionTarget.classList.remove("hidden")
            } else {
                this.eventSectionTarget.classList.add("hidden")
            }
        }
    }

    updateFilter() {
        const allSelected = document.querySelector('input[name="event_filter_mode"][value="all"]').checked

        if (allSelected) {
            // Hide checkboxes
            this.checkboxesTarget.classList.add("hidden")
            // Uncheck all event type checkboxes
            this.checkboxTargets.forEach(checkbox => {
                checkbox.checked = false
            })
            // Show all events
            this.showAllEvents()
        } else {
            // Show checkboxes
            this.checkboxesTarget.classList.remove("hidden")
            // Update event list based on checked boxes
            this.updateEventList()
        }
    }

    updateEventList() {
        const allSelected = document.querySelector('input[name="event_filter_mode"][value="all"]').checked

        if (allSelected) {
            this.showAllEvents()
            return
        }

        // Get selected event types
        const selectedTypes = this.checkboxTargets
            .filter(checkbox => checkbox.checked)
            .map(checkbox => checkbox.value)

        // Always show all events, but style based on selection
        if (this.hasEventListTarget) {
            const eventItems = this.eventListTarget.querySelectorAll('[data-event-type]')
            let selectedCount = 0

            if (selectedTypes.length === 0) {
                // If nothing selected, show all with a muted style
                eventItems.forEach(item => {
                    item.classList.remove("hidden")
                    item.classList.add("opacity-40")
                })
                selectedCount = 0
            } else {
                // Show all events, but gray out unselected ones
                eventItems.forEach(item => {
                    const eventType = item.dataset.eventType
                    item.classList.remove("hidden")
                    if (selectedTypes.includes(eventType)) {
                        item.classList.remove("opacity-40")
                        selectedCount++
                    } else {
                        item.classList.add("opacity-40")
                    }
                })
            }

            // Update count display
            this.updateCount(selectedCount)
        }
    }

    showAllEvents() {
        if (this.hasEventListTarget) {
            const eventItems = this.eventListTarget.querySelectorAll('[data-event-type]')
            eventItems.forEach(item => {
                item.classList.remove("hidden")
                item.classList.remove("opacity-40")
            })
            // When showing all events, count is the total
            this.updateCount(eventItems.length)
        }
    }

    updateCount(count) {
        if (this.hasCountTarget) {
            this.countTarget.textContent = count
        }
    }
}
