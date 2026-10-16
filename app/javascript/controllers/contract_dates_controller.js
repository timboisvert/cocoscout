import { Controller } from "@hotwired/stimulus"

// A contract's list of dates (Review the dates; each date's services): the
// kind pills filter the rows, and ticking rows offers one Edit for all of
// them, its fields only for the kinds of date that are ticked.
export default class extends Controller {
    static targets = ["pill", "row", "check", "all", "hint", "several", "section"]

    filter(event) {
        const kind = event.currentTarget.dataset.kind || ""
        this.rowTargets.forEach(row => {
            const hide = kind !== "" && row.dataset.kind !== kind
            row.classList.toggle("hidden", hide)
            if (hide) row.querySelectorAll("input[type=checkbox]").forEach(box => { box.checked = false })
        })
        this.pillTargets.forEach(pill => {
            const on = (pill.dataset.kind || "") === kind
            pill.classList.toggle("border-pink-300", on)
            pill.classList.toggle("bg-pink-50", on)
            pill.classList.toggle("text-pink-700", on)
            pill.classList.toggle("border-gray-300", !on)
            pill.classList.toggle("bg-white", !on)
            pill.classList.toggle("text-gray-700", !on)
        })
        this.changed()
    }

    toggleAll(event) {
        const on = event.currentTarget.checked
        this.visibleChecks().forEach(box => { box.checked = on })
        this.changed()
    }

    changed() {
        const ticked = this.checkTargets.filter(box => box.checked)
        const kinds = new Set(ticked.map(box => box.dataset.kind))
        if (this.hasHintTarget) this.hintTarget.classList.toggle("hidden", ticked.length > 0)
        if (this.hasSeveralTarget) {
            this.severalTarget.classList.toggle("hidden", ticked.length === 0)
            const label = this.severalTarget.querySelector("button")
            if (label) label.textContent = ticked.length === 1 ? "Edit the ticked date" : `Edit the ${ticked.length} ticked dates`
        }
        this.sectionTargets.forEach(section => {
            const on = kinds.has(section.dataset.kind)
            section.classList.toggle("hidden", !on)
            section.querySelectorAll("input, select").forEach(field => { field.disabled = !on })
        })
        if (this.hasAllTarget) {
            const visible = this.visibleChecks()
            this.allTarget.checked = visible.length > 0 && visible.every(box => box.checked)
        }
    }

    visibleChecks() {
        return this.checkTargets.filter(box => !box.closest("[data-contract-dates-target=row]")?.classList.contains("hidden"))
    }
}
