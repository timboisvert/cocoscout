import { Controller } from "@hotwired/stimulus"

// Controls hiding/showing non-revenue events in the money page list
// Uses server-side filtering with cookie persistence
export default class extends Controller {
    static targets = ["toggle"]

    toggle() {
        // Read current state from aria-checked attribute
        const currentState = this.toggleTarget.getAttribute("aria-checked") === "true"
        const newState = !currentState

        // Update URL with toggle parameter and reload via Turbo
        const url = new URL(window.location.href)
        url.searchParams.set("hide_non_revenue", newState.toString())

        // Navigate with Turbo
        Turbo.visit(url.toString())
    }
}
