import { Controller } from "@hotwired/stimulus"

// Format step of the audition wizard: show the curated-only format options only
// when "Curated" is selected. Open sign-up hides them (it's always in-person
// slot booking). Defaults to visible so the page still works without JS.
export default class extends Controller {
    static targets = ["curatedOptions"]

    connect() {
        this.update()
    }

    update() {
        const selected = this.element.querySelector('input[name="signup_mode"]:checked')
        const open = selected?.value === "open"
        if (this.hasCuratedOptionsTarget) {
            this.curatedOptionsTarget.classList.toggle("hidden", open)
        }
    }
}
