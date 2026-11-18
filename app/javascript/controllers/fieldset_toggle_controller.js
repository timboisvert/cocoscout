import { Controller } from "@hotwired/stimulus"

// A switch that brings a fieldset to life. Off, the fieldset is disabled:
// its inputs are grayed out and none of them are sent with the form. On,
// they're editable. (A date's own ticket prices: off means the production's.)
export default class extends Controller {
    static targets = ["switch", "fields"]

    // No switch (a date with nothing above it to follow): leave the fields be.

    connect() {
        this.toggle()
    }

    toggle() {
        if (!this.hasSwitchTarget) return

        const on = this.switchTarget.checked
        this.fieldsTargets.forEach((fieldset) => { fieldset.disabled = !on })
    }
}
