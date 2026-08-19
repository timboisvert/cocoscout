import { Controller } from "@hotwired/stimulus"

// The Work times rows on Staffing settings: add another "Region · from · to"
// row (named one past the last index) or remove one. Blank rows are dropped
// on save, so removing is just taking the row out of the form.
export default class extends Controller {
    static targets = ["list", "row", "template"]

    connect() {
        this.index = this.rowTargets.length
    }

    add(event) {
        if (event) event.preventDefault()
        if (!this.hasListTarget || !this.hasTemplateTarget) return

        const index = this.index++
        const fragment = this.templateTarget.content.cloneNode(true)
        fragment.querySelectorAll("input[name]").forEach(input => {
            input.name = input.name.replace("__INDEX__", index)
        })
        this.listTarget.appendChild(fragment)

        const rows = this.rowTargets
        rows[rows.length - 1]?.querySelector("input[type='text']")?.focus()
    }

    remove(event) {
        event.preventDefault()
        event.target.closest('[data-staffing-day-parts-target="row"]')?.remove()
    }
}
