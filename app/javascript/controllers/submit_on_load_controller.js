import { Controller } from "@hotwired/stimulus"

// Submits its form as soon as the page shows it: the unsubscribe page does
// the unsubscribing with a POST, so link checkers that only fetch the page
// (and never run scripts) can't unsubscribe anyone. The form's button stays
// for anyone without scripts.
export default class extends Controller {
    connect() {
        if (this.element.dataset.submitted) return
        this.element.dataset.submitted = "1"
        setTimeout(() => this.element.requestSubmit(), 0)
    }
}
