import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="bulk-select"
export default class extends Controller {
    static targets = ["checkbox", "selectAllCheckbox", "actionBar", "count", "selectCell", "selectModeButton"]

    // Phone: the checkboxes stay out of the way until Select is tapped.
    toggleSelectMode() {
        this.selectMode = !this.selectMode
        this.selectCellTargets.forEach(cell => cell.classList.toggle("max-sm:hidden", !this.selectMode))
        if (this.hasSelectModeButtonTarget) {
            this.selectModeButtonTarget.textContent = this.selectMode ? "Done" : "Select"
            this.selectModeButtonTarget.classList.toggle("border-pink-500", this.selectMode)
            this.selectModeButtonTarget.classList.toggle("text-pink-700", this.selectMode)
        }
        if (!this.selectMode) {
            this.checkboxTargets.forEach(cb => { cb.checked = false })
            this.update()
        }
    }

    connect() {
        this.update()
    }

    toggle() {
        this.update()
    }

    toggleAll() {
        const checked = this.selectAllCheckboxTarget.checked
        this.checkboxTargets.forEach(cb => { cb.checked = checked })
        this.update()
    }

    update() {
        const checked = this.checkboxTargets.filter(cb => cb.checked)
        const total = this.checkboxTargets.length
        const count = checked.length

        if (this.hasActionBarTarget) {
            this.actionBarTarget.classList.toggle("hidden", count === 0)
        }

        if (this.hasCountTarget) {
            this.countTarget.textContent = `${count} selected`
        }

        if (this.hasSelectAllCheckboxTarget) {
            this.selectAllCheckboxTarget.checked = count > 0 && count === total
            this.selectAllCheckboxTarget.indeterminate = count > 0 && count < total
        }
    }
}
