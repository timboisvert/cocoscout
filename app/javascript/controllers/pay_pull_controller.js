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

    // Total hours and total worked pay (each entry at its own role's rate) for
    // the currently checked entries.
    totals() {
        return this.checkedEntries().reduce((acc, c) => {
            const hours = parseFloat(c.dataset.hours) || 0
            const rateCents = parseFloat(c.dataset.rateCents) || 0
            acc.hours += hours
            acc.workedCents += Math.round(rateCents * hours)
            return acc
        }, { hours: 0, workedCents: 0 })
    }

    recalcSubtotal() {
        const { hours, workedCents } = this.totals()
        if (this.hasSubtotalTarget) {
            this.subtotalTarget.textContent = `${Math.round(hours * 100) / 100} hrs · $${(workedCents / 100).toFixed(2)}`
        }
    }

    include(event) {
        if (event) event.preventDefault()
        const checked = this.checkedEntries()
        const { hours, workedCents } = this.totals()

        const hoursInput = document.getElementById(`pay-hours-${this.memberId}`)
        if (hoursInput) {
            hoursInput.value = Math.round(hours * 100) / 100
            // Pulled entries are paid per-role, so hand the computed worked pay to
            // the row for the live total (the server recomputes it authoritatively).
            const row = hoursInput.closest('[data-pay-run-target="row"]')
            if (row) row.dataset.workedCents = String(workedCents)
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
