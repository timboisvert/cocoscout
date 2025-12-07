import { Controller } from "@hotwired/stimulus"

// Controls the Features card visibility and radio/checkbox interactions
export default class extends Controller {
    static targets = [
        "eventPagesOptions", "eventPagesSpecific",
        "upcomingEventsOptions", "upcomingEventsSpecific"
    ]

    connect() {
        // Initial visibility is handled by server-side rendering
    }

    // Toggle for auto_create_event_pages
    toggleEventPages(event) {
        const enabled = event.target.checked
        if (this.hasEventPagesOptionsTarget) {
            this.eventPagesOptionsTarget.classList.toggle("hidden", !enabled)
        }
        if (this.hasEventPagesSpecificTarget && !enabled) {
            this.eventPagesSpecificTarget.classList.add("hidden")
        }
        event.target.form.requestSubmit()
    }

    // Radio change for event pages mode
    changeEventPagesMode(event) {
        const mode = event.target.value
        if (this.hasEventPagesSpecificTarget) {
            this.eventPagesSpecificTarget.classList.toggle("hidden", mode !== "specific")
        }
        // Submit the form after visibility change
        event.target.form.requestSubmit()
    }

    // Toggle for show_upcoming_events
    toggleUpcomingEvents(event) {
        const enabled = event.target.checked
        if (this.hasUpcomingEventsOptionsTarget) {
            this.upcomingEventsOptionsTarget.classList.toggle("hidden", !enabled)
        }
        if (this.hasUpcomingEventsSpecificTarget && !enabled) {
            this.upcomingEventsSpecificTarget.classList.add("hidden")
        }
        event.target.form.requestSubmit()
    }

    // Radio change for upcoming events mode
    changeUpcomingEventsMode(event) {
        const mode = event.target.value
        if (this.hasUpcomingEventsSpecificTarget) {
            this.upcomingEventsSpecificTarget.classList.toggle("hidden", mode !== "specific")
        }
        // Submit the form after visibility change
        event.target.form.requestSubmit()
    }

    // Generic submit for checkboxes
    submitForm(event) {
        event.target.form.requestSubmit()
    }
}
