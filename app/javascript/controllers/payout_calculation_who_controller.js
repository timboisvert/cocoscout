import { Controller } from "@hotwired/stimulus"

// The wizard's "Who uses it" step (manage/payout_calculation_wizard/who).
// Shows the "Will switch from X" note under a production only while it's
// checked, and reveals the date input when the switch starts on a date.
export default class extends Controller {
    static targets = ["date"]

    toggleNote(event) {
        const note = document.getElementById(event.target.dataset.noteId)
        if (note) note.classList.toggle("hidden", !event.target.checked)
    }

    toggleDate() {
        if (!this.hasDateTarget) return
        const onDate = this.element.querySelector('input[name="starting"]:checked')?.value === "date"
        this.dateTarget.classList.toggle("hidden", !onDate)
        if (onDate) this.dateTarget.focus()
    }
}
