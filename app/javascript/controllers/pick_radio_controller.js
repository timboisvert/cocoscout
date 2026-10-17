import { Controller } from "@hotwired/stimulus"

// A field inside a radio card ("A set number [10] per date"): focusing or
// typing in it picks that card's radio, since a click on the field itself
// doesn't activate the label.
export default class extends Controller {
    pick(event) {
        const card = event.currentTarget.closest("label")
        const radio = card && card.querySelector("input[type=radio]")
        if (radio && !radio.checked) {
            radio.checked = true
            radio.dispatchEvent(new Event("change", { bubbles: true }))
        }
    }
}
