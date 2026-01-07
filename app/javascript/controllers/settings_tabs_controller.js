import { Controller } from "@hotwired/stimulus"

// Controller to manage dynamic tabs based on scope selection
// When scope changes, the tabs update to show/hide the Events tab
export default class extends Controller {
    static targets = ["eventsTab", "eventsPanel"]
    static values = { scope: String }

    connect() {
        this.updateTabs()
    }

    scopeChanged(event) {
        this.scopeValue = event.target.value
        this.updateTabs()
    }

    updateTabs() {
        const scope = this.scopeValue || this.getCurrentScope()
        const showEventsTab = scope !== "shared_pool"

        if (this.hasEventsTabTarget) {
            this.eventsTabTarget.classList.toggle("hidden", !showEventsTab)
        }
    }

    getCurrentScope() {
        const checked = this.element.querySelector('input[name="sign_up_form[scope]"]:checked')
        return checked ? checked.value : "single_event"
    }
}
