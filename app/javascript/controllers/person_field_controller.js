import { Controller } from "@hotwired/stimulus"

// A form's person, found by the shared People Picker (shared/_people_picker):
// the pick's id goes in a hidden field, and their name on the button that
// opened the picker. Sending the form with nobody picked opens the picker
// instead. Hears people-picker:pick on window, so the picker's sheet can sit
// outside the form (its search box must: Enter there would send the form).
export default class extends Controller {
    static targets = ["field", "opener", "next"]
    static values = { pickerId: String }

    picked(event) {
        const pick = event.detail
        if (pick.picker !== this.pickerIdValue || pick.type !== "Person") return
        this.fieldTarget.value = pick.id
        const label = this.openerTarget.querySelector("span") || this.openerTarget
        label.textContent = pick.name
        if (this.hasNextTarget) {
            this.nextTarget.focus()
            this.nextTarget.select?.()
        }
    }

    check(event) {
        if (this.fieldTarget.value) return
        event.preventDefault()
        this.openerTarget.click()
    }
}
