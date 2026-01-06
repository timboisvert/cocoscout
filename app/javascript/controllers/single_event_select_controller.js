import { Controller } from "@hotwired/stimulus"

// Controller for selecting a single event from a list (click-to-select, no radio buttons visible)
export default class extends Controller {
    static targets = ["row", "input", "checkmark"]
    static values = { selectedId: String }

    connect() {
        this.updateSelection()
    }

    select(event) {
        const row = event.currentTarget
        const showId = row.dataset.showId

        // Find the hidden input for this row and select it
        const input = this.inputTargets.find(i => i.value === showId)
        if (input) {
            input.checked = true
            this.selectedIdValue = showId
            this.updateSelection()
        }
    }

    updateSelection() {
        this.rowTargets.forEach(row => {
            const showId = row.dataset.showId
            const isSelected = showId === this.selectedIdValue
            const checkmark = row.querySelector('[data-single-event-select-target="checkmark"]')

            if (isSelected) {
                row.classList.remove("border-gray-200", "bg-white")
                row.classList.add("border-pink-500", "bg-pink-50")
                if (checkmark) {
                    checkmark.innerHTML = `<div class="w-6 h-6 rounded-full bg-pink-500 flex items-center justify-center">
            <svg class="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
            </svg>
          </div>`
                }
            } else {
                row.classList.remove("border-pink-500", "bg-pink-50")
                row.classList.add("border-gray-200", "bg-white")
                if (checkmark) {
                    checkmark.innerHTML = `<div class="w-6 h-6 rounded-full border-2 border-gray-300"></div>`
                }
            }
        })
    }

    selectedIdValueChanged() {
        this.updateSelection()
    }
}
