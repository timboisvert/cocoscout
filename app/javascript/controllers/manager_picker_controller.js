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
        this.pendingHeadshot = row.dataset.headshot || ""
        this.pendingInitials = row.dataset.initials || "?"
        this.rowTargets.forEach(r => {
            const on = r === row
            r.classList.toggle("ring-2", on)
            r.classList.toggle("ring-pink-400", on)
            r.classList.toggle("bg-pink-50", on)
        })
        this.updateSelectButton()
    }

    confirm(event) {
        if (event) event.preventDefault()
        if (!this.pendingId) return
        this.inputTarget.value = this.pendingId
        this.displayTarget.innerHTML = this.chipHtml(this.pendingName, this.pendingHeadshot, this.pendingInitials)
        this.close()
    }

    clear(event) {
        if (event) event.preventDefault()
        this.inputTarget.value = ""
        this.pendingId = ""
        this.displayTarget.innerHTML = `<span class="text-sm text-gray-400">No manager</span>`
        this.close()
    }

    // Matches the server-rendered _manager_chip partial.
    chipHtml(name, headshot, initials) {
        const avatar = headshot
            ? `<img src="${this.escape(headshot)}" alt="${this.escape(name)}" class="w-6 h-6 rounded-full object-cover">`
            : `<span class="w-6 h-6 rounded-full bg-gray-200 flex items-center justify-center text-[10px] font-bold text-gray-600">${this.escape(initials)}</span>`
        return `<span class="inline-flex items-center gap-2 pl-1 pr-3 py-1 rounded-full border border-gray-300 bg-white shadow-sm">${avatar}<span class="text-sm font-medium text-gray-900">${this.escape(name)}</span></span>`
    }

    escape(str) {
        const d = document.createElement("div")
        d.textContent = String(str == null ? "" : str)
        return d.innerHTML
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
