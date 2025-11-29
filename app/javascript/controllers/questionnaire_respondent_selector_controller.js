import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["dropdownMenu", "dropdownChevron", "respondentType", "respondentId"]

    toggleDropdown() {
        this.dropdownMenuTarget.classList.toggle("hidden")
        this.dropdownChevronTarget.classList.toggle("rotate-180")
    }

    selectRespondent(event) {
        const button = event.currentTarget
        const type = button.dataset.type
        const id = button.dataset.id

        // Update hidden fields
        this.respondentTypeTarget.value = type
        this.respondentIdTarget.value = id

        // Reload the page with new respondent selection
        const url = new URL(window.location.href)
        url.searchParams.set('respondent_type', type)
        url.searchParams.set('respondent_id', id)
        window.location.href = url.toString()
    }

    disconnect() {
        // Close dropdown when controller is disconnected
        if (this.hasDropdownMenuTarget) {
            this.dropdownMenuTarget.classList.add("hidden")
        }
    }
}
