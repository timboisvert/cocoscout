import { Controller } from "@hotwired/stimulus"

// Pull a person's confirmed/unpaid worked hours into their pay-grid row. The
// "pull Nh" link opens a shared modal, loads that person's unpaid time entries
// into a Turbo-frame, and "Include" sums the checked entries into the row's
// Hours input and records their ids in hidden inputs so the run ties them.
export default class extends Controller {
    static targets = ["modal", "frame", "subtotal"]

    open(event) {
        if (event) event.preventDefault()
        this.memberId = event.currentTarget.dataset.memberId
        if (this.hasFrameTarget) this.frameTarget.src = event.currentTarget.dataset.src
        this.modalTarget.classList.remove("hidden")
        // Subtotal refreshes once the frame's checkboxes render.
        setTimeout(() => this.recalcSubtotal(), 150)
    }

    close(event) {
        if (event) event.preventDefault()
        this.modalTarget.classList.add("hidden")
    }

    backdropClose(event) {
        if (event.target === this.modalTarget) this.close(event)
    }

    stopPropagation(event) { event.stopPropagation() }

    checkedEntries() {
        if (!this.hasFrameTarget) return []
        return Array.from(this.frameTarget.querySelectorAll('input[data-entry-id]:checked'))
    }

    recalcSubtotal() {
        const sum = this.checkedEntries().reduce((a, c) => a + (parseFloat(c.dataset.hours) || 0), 0)
        if (this.hasSubtotalTarget) this.subtotalTarget.textContent = String(Math.round(sum * 100) / 100)
    }

    include(event) {
        if (event) event.preventDefault()
        const checked = this.checkedEntries()
        const sum = checked.reduce((a, c) => a + (parseFloat(c.dataset.hours) || 0), 0)

        const hoursInput = document.getElementById(`pay-hours-${this.memberId}`)
        if (hoursInput) {
            hoursInput.value = Math.round(sum * 100) / 100
            hoursInput.dispatchEvent(new Event("input", { bubbles: true })) // triggers pay-run#recalc
        }
        const holder = document.getElementById(`pay-entries-${this.memberId}`)
        if (holder) {
            holder.innerHTML = checked
                .map(c => `<input type="hidden" name="lines[${this.memberId}][time_entry_ids][]" value="${c.dataset.entryId}">`)
                .join("")
        }
        this.close()
    }
}
