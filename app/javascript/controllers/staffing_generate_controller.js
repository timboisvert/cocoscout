import { Controller } from "@hotwired/stimulus"

// Opens the "Generate shifts" modal and lets the manager pick which shows to
// staff before submitting. Checkboxes default to all-checked; All/None toggle
// them in bulk.
export default class extends Controller {
    static targets = ["modal", "showCheckbox"]

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

    selectAll(event) {
        if (event) event.preventDefault()
        this.showCheckboxTargets.forEach(cb => { cb.checked = true })
    }

    selectNone(event) {
        if (event) event.preventDefault()
        this.showCheckboxTargets.forEach(cb => { cb.checked = false })
    }

    show() { if (this.hasModalTarget) this.modalTarget.classList.remove("hidden") }
    hide() { if (this.hasModalTarget) this.modalTarget.classList.add("hidden") }
}
