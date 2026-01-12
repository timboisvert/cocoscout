import { Controller } from "@hotwired/stimulus"

// Controls the restricted role invite UI - switching between eligible-only and all members
export default class extends Controller {
    static targets = ["poolRadio", "eligibleSection", "allSection", "eligibleCheckbox", "allCheckbox"]

    connect() {
        this.updatePool()
    }

    updatePool() {
        const selectedMode = this.poolRadioTargets.find(r => r.checked)?.value || "eligible"

        if (selectedMode === "eligible") {
            this.eligibleSectionTarget.classList.remove("hidden")
            this.allSectionTarget.classList.add("hidden")
            // Disable all checkboxes in the hidden section so they don't submit
            this.allCheckboxTargets.forEach(cb => cb.disabled = true)
            // Re-enable eligible checkboxes (except ones that were originally disabled)
            this.eligibleCheckboxTargets.forEach(cb => {
                if (!cb.dataset.originallyDisabled) {
                    cb.disabled = false
                }
            })
        } else {
            this.eligibleSectionTarget.classList.add("hidden")
            this.allSectionTarget.classList.remove("hidden")
            // Disable eligible checkboxes so they don't submit
            this.eligibleCheckboxTargets.forEach(cb => cb.disabled = true)
            // Re-enable all checkboxes (except ones that were originally disabled)
            this.allCheckboxTargets.forEach(cb => {
                if (!cb.dataset.originallyDisabled) {
                    cb.disabled = false
                }
            })
        }
    }
}
