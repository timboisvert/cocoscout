import { Controller } from "@hotwired/stimulus"

// The Pay People grid hides excluded (Staffing settings) and inactive members
// by default. A bar under the grid shows how many are hidden; its picker modal
// reveals them one at a time for a one-off payment. Nothing persists — the
// next page load hides them again.
//
// autoReveal guards the draft path: a restored draft can carry values for a
// row that's hidden this visit (revealed last time, or excluded since). Money
// must never sit in an invisible row, so any hidden row with something entered
// gets revealed as soon as the draft (or any input) touches the form.
export default class extends Controller {
    static targets = ["row", "bar", "picker", "count"]

    openPicker(event) {
        if (event) event.preventDefault()
        this.pickerTarget.classList.remove("hidden")
    }

    closePicker(event) {
        if (event) event.preventDefault()
        this.pickerTarget.classList.add("hidden")
    }

    closeOnBackdrop(event) {
        if (event.target === this.pickerTarget) this.closePicker(event)
    }

    stopPropagation(event) { event.stopPropagation() }

    reveal(event) {
        event.preventDefault()
        this.revealMember(event.currentTarget.dataset.memberId)
    }

    // Fired on any form input (including the draft restore's synthetic event):
    // reveal hidden rows that have values so nothing invisible can submit.
    autoReveal() {
        this.hiddenRows().forEach(row => {
            const hasValue = Array.from(row.querySelectorAll('input[name^="lines["]'))
                .some(input => (input.value || "").trim() !== "" && parseFloat(input.value) !== 0)
            if (hasValue) this.revealMember(row.dataset.memberId)
        })
    }

    // ---- helpers ----

    hiddenRows() {
        return this.rowTargets.filter(row => row.dataset.hiddenFromPay === "true")
    }

    revealMember(memberId) {
        this.rowTargets
            .filter(row => row.dataset.memberId === String(memberId))
            .forEach(row => {
                row.style.display = ""
                // Clear the flag so pay-confirm's checks treat the row as live.
                row.dataset.hiddenFromPay = "false"
            })

        // Drop them from the picker; update the count; hide the bar (and close
        // the picker) once everyone's revealed.
        if (!this.hasPickerTarget) return
        this.pickerTarget.querySelector(`[data-hidden-person][data-member-id="${memberId}"]`)?.remove()
        const remaining = this.pickerTarget.querySelectorAll("[data-hidden-person]").length
        if (this.hasCountTarget) this.countTarget.textContent = `${remaining} ${remaining === 1 ? "person" : "people"}`
        if (remaining === 0) {
            this.closePicker()
            if (this.hasBarTarget) this.barTarget.classList.add("hidden")
        }
    }
}
