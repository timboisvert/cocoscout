import { Controller } from "@hotwired/stimulus"

// A casting table's Talent Pool tab: the shared People Picker ("table-picker",
// the organization's people and groups) picks who to add; the pick posts the
// page's add-member form, which comes back with them listed.
export default class extends Controller {
    static targets = ["form", "type", "id"]

    picked(event) {
        const pick = event.detail
        if (pick.picker !== "table-picker" || !pick.type) return
        this.typeTarget.value = pick.type
        this.idTarget.value = pick.id
        this.formTarget.requestSubmit()
    }
}
