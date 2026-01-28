import { Controller } from "@hotwired/stimulus"

// Controls hiding/showing non-revenue events in the money page list
// Uses server-side filtering with cookie persistence
export default class extends Controller {
    toggle(event) {
        // Read current state from aria-checked attribute
        const button = event.currentTarget
        const currentState = button.getAttribute("aria-checked") === "true"
        const newState = !currentState

        // Update URL with toggle parameter and reload via Turbo
        const url = new URL(window.location.href)
        url.searchParams.set("hide_non_revenue", newState.toString())

        // Navigate with Turbo
        Turbo.visit(url.toString())
    }

    toggleFutureEvents(event) {
        // Read current state from aria-checked attribute
        const button = event.currentTarget
        const currentState = button.getAttribute("aria-checked") === "true"
        const newState = !currentState

        // Update URL with toggle parameter and reload via Turbo
        const url = new URL(window.location.href)
        url.searchParams.set("hide_future_events", newState.toString())

        // Navigate with Turbo
        Turbo.visit(url.toString())
    }
}
