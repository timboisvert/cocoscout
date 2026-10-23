import { Controller } from "@hotwired/stimulus"

// Turns a pick in the shared people picker into a form post: the picked
// person's id goes in the hidden field and the form submits. Mailing lists'
// "Change who can see it" uses it.
export default class extends Controller {
    static targets = ["field"]

    picked(event) {
        const detail = event.detail || {}
        if (!detail.id || detail.type === "Group") return
        this.fieldTarget.value = detail.id
        this.element.requestSubmit()
    }
}
