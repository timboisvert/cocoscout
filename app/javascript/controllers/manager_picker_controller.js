import { Controller } from "@hotwired/stimulus"

// A click-in modal for choosing a staff member's manager instead of a dropdown.
// The trigger shows the current selection ("No manager" when empty). Opening it
// lists all staff, filters as you type, and highlights the row you tap; "Select
// as manager" commits the choice into the hidden field.
export default class extends Controller {
    static targets = ["modal", "input", "display", "search", "row", "selectButton"]

    connect() {
        this.pendingId = this.inputTarget.value || ""
        this.pendingName = ""
    }

    open(event) {
        if (event) event.preventDefault()
        this.pendingId = this.inputTarget.value || ""
        this.highlightCurrent()
        this.updateSelectButton()
        if (this.hasSearchTarget) { this.searchTarget.value = ""; this.filter() }
        this.modalTarget.classList.remove("hidden")
        setTimeout(() => this.searchTarget?.focus(), 50)
    }

    close(event) {
        if (event) event.preventDefault()
        this.modalTarget.classList.add("hidden")
    }

    backdropClose(event) {
        if (event.target === this.modalTarget) this.close(event)
    }

    stopPropagation(event) { event.stopPropagation() }

    filter() {
        const q = (this.searchTarget.value || "").trim().toLowerCase()
        this.rowTargets.forEach(r => {
            const match = q.length === 0 || (r.dataset.name || "").includes(q)
            r.classList.toggle("hidden", !match)
        })
    }

    choose(event) {
        const row = event.currentTarget
        this.pendingId = row.dataset.id
        this.pendingName = row.dataset.display
        this.rowTargets.forEach(r => r.classList.toggle("ring-2", r === row))
        this.rowTargets.forEach(r => r.classList.toggle("ring-pink-400", r === row))
        this.rowTargets.forEach(r => r.classList.toggle("bg-pink-50", r === row))
        this.updateSelectButton()
    }

    confirm(event) {
        if (event) event.preventDefault()
        if (!this.pendingId) return
        this.inputTarget.value = this.pendingId
        this.displayTarget.textContent = this.pendingName || "Selected"
        this.displayTarget.classList.remove("text-gray-400")
        this.displayTarget.classList.add("text-gray-900")
        this.close()
    }

    clear(event) {
        if (event) event.preventDefault()
        this.inputTarget.value = ""
        this.pendingId = ""
        this.displayTarget.textContent = "No manager"
        this.displayTarget.classList.add("text-gray-400")
        this.displayTarget.classList.remove("text-gray-900")
        this.close()
    }

    highlightCurrent() {
        this.rowTargets.forEach(r => {
            const on = r.dataset.id === this.pendingId
            r.classList.toggle("ring-2", on)
            r.classList.toggle("ring-pink-400", on)
            r.classList.toggle("bg-pink-50", on)
            if (on) this.pendingName = r.dataset.display
        })
    }

    updateSelectButton() {
        if (this.hasSelectButtonTarget) this.selectButtonTarget.disabled = !this.pendingId
    }
}
