import { Controller } from "@hotwired/stimulus"

// Controls the Issue Advances modal form
// - Updates all person amounts when default amount changes (unless manually edited)
// - Shows/hides exclude reason when checkbox is toggled
// - Persists exclude state to localStorage
export default class extends Controller {
    static targets = ["defaultAmount", "personAmount", "excludeCheckbox", "amountRow", "personRow", "excludeReason"]
    static values = { showId: Number }

    connect() {
        // Track which amounts have been manually edited
        this.editedAmounts = new Set()
        // Load saved exclude states from localStorage
        this.loadPersistedState()
    }

    // Called when default amount changes - update only non-edited amounts
    updateAllAmounts() {
        const defaultAmount = parseFloat(this.defaultAmountTarget.value) || 0

        this.personAmountTargets.forEach((input) => {
            const personId = input.closest("[data-person-id]")?.dataset.personId
            // Only update if the input hasn't been manually edited
            if (!this.editedAmounts.has(personId)) {
                input.value = defaultAmount.toFixed(0)
            }
        })
    }

    // Track when a person's amount is manually edited
    markAsEdited(event) {
        const personId = event.target.closest("[data-person-id]")?.dataset.personId
        if (personId) {
            this.editedAmounts.add(personId)
        }
    }

    toggleExcluded(event) {
        const checkbox = event.target
        const row = checkbox.closest("[data-advance-form-target='personRow']")
        const amountRow = row.querySelector("[data-advance-form-target='amountRow']")
        const reasonRow = row.querySelector("[data-advance-form-target='excludeReason']")
        const personId = row.dataset.personId

        if (checkbox.checked) {
            // Hide amount, show reason
            if (amountRow) amountRow.classList.add("hidden")
            if (reasonRow) reasonRow.classList.remove("hidden")
        } else {
            // Show amount, hide reason
            if (amountRow) amountRow.classList.remove("hidden")
            if (reasonRow) reasonRow.classList.add("hidden")
        }

        // Persist to localStorage
        this.saveExcludeState(personId, checkbox.checked, reasonRow?.querySelector("select")?.value)
    }

    onReasonChange(event) {
        const row = event.target.closest("[data-advance-form-target='personRow']")
        const personId = row.dataset.personId
        const checkbox = row.querySelector("[data-advance-form-target='excludeCheckbox']")

        // Persist to localStorage
        this.saveExcludeState(personId, checkbox?.checked, event.target.value)
    }

    getStorageKey() {
        return `advance_excludes_${this.showIdValue}`
    }

    saveExcludeState(personId, excluded, reason) {
        const key = this.getStorageKey()
        const data = JSON.parse(localStorage.getItem(key) || "{}")

        if (excluded) {
            data[personId] = { excluded: true, reason: reason || "" }
        } else {
            delete data[personId]
        }

        localStorage.setItem(key, JSON.stringify(data))
    }

    loadPersistedState() {
        const key = this.getStorageKey()
        const data = JSON.parse(localStorage.getItem(key) || "{}")

        this.personRowTargets.forEach((row) => {
            const personId = row.dataset.personId
            const saved = data[personId]

            if (saved?.excluded) {
                const checkbox = row.querySelector("[data-advance-form-target='excludeCheckbox']")
                const amountRow = row.querySelector("[data-advance-form-target='amountRow']")
                const reasonRow = row.querySelector("[data-advance-form-target='excludeReason']")
                const reasonSelect = reasonRow?.querySelector("select")

                if (checkbox) {
                    checkbox.checked = true
                    if (amountRow) amountRow.classList.add("hidden")
                    if (reasonRow) reasonRow.classList.remove("hidden")
                    if (reasonSelect && saved.reason) reasonSelect.value = saved.reason
                }
            }
        })
    }
}
