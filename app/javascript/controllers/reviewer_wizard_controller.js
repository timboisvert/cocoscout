import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "managersRadio", "allRadio", "specificRadio",
        "managersToggle", "managersList",
        "talentPoolToggle", "talentPoolList",
        "specificSection"
    ]

    toggleSection(event) {
        const value = event.target.value

        if (this.hasSpecificSectionTarget) {
            this.specificSectionTarget.classList.toggle("hidden", value !== "specific")
        }
    }

    toggleManagersList(event) {
        event.preventDefault()
        if (this.hasManagersListTarget) {
            const isHidden = this.managersListTarget.classList.contains("hidden")
            this.managersListTarget.classList.toggle("hidden")
            if (this.hasManagersToggleTarget) {
                const count = this.managersListTarget.querySelectorAll('.text-center').length
                this.managersToggleTarget.textContent = isHidden ? "Hide" : `Show ${count} ${count === 1 ? 'person' : 'people'}`
            }
        }
    }

    toggleTalentPoolList(event) {
        event.preventDefault()
        if (this.hasTalentPoolListTarget) {
            const isHidden = this.talentPoolListTarget.classList.contains("hidden")
            this.talentPoolListTarget.classList.toggle("hidden")
            if (this.hasTalentPoolToggleTarget) {
                const count = this.talentPoolListTarget.querySelectorAll('.text-center').length
                this.talentPoolToggleTarget.textContent = isHidden ? "Hide" : `Show ${count} ${count === 1 ? 'person' : 'people'}`
            }
        }
    }
}
