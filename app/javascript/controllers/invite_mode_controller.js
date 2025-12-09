import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="invite-mode"
export default class extends Controller {
    static targets = ["modeRadio", "specificPeopleSection", "poolDropdown", "peopleList"]

    connect() {
        this.updateMode()
    }

    updateMode() {
        const selectedMode = this.modeRadioTargets.find(radio => radio.checked)?.value

        // Show/hide specific people section
        if (this.hasSpecificPeopleSectionTarget) {
            if (selectedMode === "specific") {
                this.specificPeopleSectionTarget.classList.remove("hidden")
            } else {
                this.specificPeopleSectionTarget.classList.add("hidden")
                // Uncheck all checkboxes when switching away from specific
                this.specificPeopleSectionTarget.querySelectorAll('input[type="checkbox"]').forEach(cb => {
                    cb.checked = false
                })
            }
        }

        // Show/hide pool dropdown
        if (this.hasPoolDropdownTarget) {
            if (selectedMode === "pool") {
                this.poolDropdownTarget.classList.remove("hidden")
            } else {
                this.poolDropdownTarget.classList.add("hidden")
            }
        }
    }

    togglePeopleList() {
        if (this.hasPeopleListTarget) {
            this.peopleListTarget.classList.toggle("hidden")
        }
    }
}
