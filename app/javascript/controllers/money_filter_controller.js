import { Controller } from "@hotwired/stimulus"
import { visitPage } from "controllers/lib/page_frame"

// Controls hiding/showing non-revenue events in the money page list
// Uses server-side filtering with cookie persistence
export default class extends Controller {
    toggle(event) {
        // Read current state from aria-checked attribute
        const button = event.currentTarget
        const currentState = button.getAttribute("aria-checked") === "true"
        const newState = !currentState

        // Update URL with toggle parameter and load it into the page
        const url = new URL(window.location.href)
        url.searchParams.set("hide_non_revenue", newState.toString())

        // Only the page's content changes (page_frame)
        visitPage(url)
    }

    toggleFutureEvents(event) {
        // Read current state from aria-checked attribute
        const button = event.currentTarget
        const currentState = button.getAttribute("aria-checked") === "true"
        const newState = !currentState

        // Update URL with toggle parameter and load it into the page
        const url = new URL(window.location.href)
        url.searchParams.set("hide_future_events", newState.toString())

        // Only the page's content changes (page_frame)
        visitPage(url)
    }
}
