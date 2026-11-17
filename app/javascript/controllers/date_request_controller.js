import { Controller } from "@hotwired/stimulus"

// The Request date/time change form on My Contracts (my/contract_date_requests/new).
// Which date and what's needed decide the rest: a day and time for a move
// or a date to add, none for a cancel or a question, and a note that a
// question can't go without.
export default class extends Controller {
    static targets = ["date", "kinds", "when", "whenLabel", "whenField", "note", "noteHint"]

    connect() {
        this.changed()
    }

    changed(event) {
        const adding = this.dateTarget.value === "new"
        const kind = adding ? "add" : (this.element.querySelector('input[name="kind"]:checked')?.value || "move")
        const timed = kind === "move" || kind === "add"

        this.kindsTarget.classList.toggle("hidden", adding)
        this.whenTarget.classList.toggle("hidden", !timed)
        this.whenFieldTarget.disabled = !timed
        this.whenFieldTarget.required = timed
        this.whenLabelTarget.textContent = adding ? "The day and time to add" : "New day and time"

        // Picking another date starts its new time from where it is now.
        if (event && event.currentTarget === this.dateTarget && !adding) {
            const at = this.dateTarget.selectedOptions[0]?.dataset.at
            if (at) this.whenFieldTarget.value = at
        }

        const question = kind === "question"
        this.noteTarget.required = question
        this.noteHintTarget.textContent = question ? "(what would you like to ask?)" : "(optional)"
    }
}
