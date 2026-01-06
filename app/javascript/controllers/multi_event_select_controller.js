import { Controller } from "@hotwired/stimulus"

// Controller for multi-select show rows (click to toggle selection)
export default class extends Controller {
    static targets = ["row", "input"]

    connect() {
        this.updateAllRows()
    }

    toggle(event) {
        const row = event.currentTarget
        const showId = row.dataset.showId

        // Find the hidden checkbox for this row and toggle it
        const input = this.inputTargets.find(i => i.value === showId)
        if (input) {
            input.checked = !input.checked
            this.updateRow(row, input.checked)
        }
    }

    updateRow(row, isSelected) {
        const checkmark = row.querySelector('[data-checkmark]')

        if (isSelected) {
            row.classList.remove("border-gray-200", "bg-white")
            row.classList.add("border-pink-500", "bg-pink-50")
            if (checkmark) {
                checkmark.innerHTML = `
          <div class="w-6 h-6 rounded-full bg-pink-500 flex items-center justify-center">
            <svg class="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
            </svg>
          </div>
        `
            }
        } else {
            row.classList.remove("border-pink-500", "bg-pink-50")
            row.classList.add("border-gray-200", "bg-white")
            if (checkmark) {
                checkmark.innerHTML = `<div class="w-6 h-6 rounded-full border-2 border-gray-300"></div>`
            }
        }
    }

    updateAllRows() {
        this.rowTargets.forEach(row => {
            const showId = row.dataset.showId
            const input = this.inputTargets.find(i => i.value === showId)
            if (input) {
                this.updateRow(row, input.checked)
            }
        })
    }
}
