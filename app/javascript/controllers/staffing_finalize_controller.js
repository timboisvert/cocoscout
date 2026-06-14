import { Controller } from "@hotwired/stimulus"

// Opens the "Finalize & notify" modal, which previews who will be notified and
// lets the manager edit the message before sending. Replaces the old
// turbo_confirm alert.
export default class extends Controller {
    static targets = ["modal"]

    open(event) {
        if (event) event.preventDefault()
        this.show()
    }

    close(event) {
        if (event) event.preventDefault()
        this.hide()
    }

    backdropClose(event) {
        if (event.target === this.modalTarget) this.hide()
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    show() { if (this.hasModalTarget) this.modalTarget.classList.remove("hidden") }
    hide() { if (this.hasModalTarget) this.modalTarget.classList.add("hidden") }
}
