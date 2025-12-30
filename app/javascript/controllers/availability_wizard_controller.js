import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "showAvailabilityToggle", "showAvailabilitySection",
        "auditionAvailabilityToggle", "auditionAvailabilitySection",
        "showList", "showCheckbox"
    ]

    toggleSection(event) {
        const isChecked = event.target.checked
        if (this.hasShowAvailabilitySectionTarget) {
            this.showAvailabilitySectionTarget.classList.toggle("hidden", !isChecked)
        }
    }

    toggleAuditionSection(event) {
        const isChecked = event.target.checked
        if (this.hasAuditionAvailabilitySectionTarget) {
            this.auditionAvailabilitySectionTarget.classList.toggle("hidden", !isChecked)
        }
    }

    selectAllShows() {
        if (this.hasShowCheckboxTarget) {
            this.showCheckboxTargets.forEach(checkbox => {
                checkbox.checked = true
            })
        }
    }
}
