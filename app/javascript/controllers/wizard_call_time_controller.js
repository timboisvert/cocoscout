import { Controller } from "@hotwired/stimulus"

// Show/hide the "how long before" offset field when the call-time toggle is on.
export default class extends Controller {
    static targets = ["toggle", "fields"]

    connect() { this.sync() }

    sync() {
        if (this.hasFieldsTarget && this.hasToggleTarget) {
            this.fieldsTarget.classList.toggle("hidden", !this.toggleTarget.checked)
        }
    }
}
