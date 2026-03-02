import { Controller } from "@hotwired/stimulus"

/**
 * Controller for selecting existing contractors in the contract wizard.
 * Populates form fields when a contractor is selected from the dropdown.
 */
export default class extends Controller {
    static targets = ["select", "fields", "name", "email", "phone", "address", "contactFields"]

    connect() {
        this.contractors = this.loadContractors()
    }

    loadContractors() {
        const template = document.getElementById("contractors-data")
        if (!template) return []

        try {
            return JSON.parse(template.innerHTML)
        } catch (e) {
            console.error("Failed to parse contractors data:", e)
            return []
        }
    }

    selectContractor(event) {
        const contractorId = event.target.value

        if (!contractorId) {
            // "Create new" selected - clear fields and enable editing
            this.clearFields()
            this.enableFields()
            return
        }

        const contractor = this.contractors.find(c => c.id.toString() === contractorId)
        if (!contractor) return

        // Populate fields with contractor data
        this.populateFields(contractor)
    }

    populateFields(contractor) {
        if (this.hasNameTarget) {
            this.nameTarget.value = contractor.name || ""
        }
        if (this.hasEmailTarget) {
            this.emailTarget.value = contractor.email || ""
        }
        if (this.hasPhoneTarget) {
            this.phoneTarget.value = contractor.phone || ""
        }
        if (this.hasAddressTarget) {
            this.addressTarget.value = contractor.address || ""
        }
    }

    clearFields() {
        if (this.hasNameTarget) {
            this.nameTarget.value = ""
        }
        if (this.hasEmailTarget) {
            this.emailTarget.value = ""
        }
        if (this.hasPhoneTarget) {
            this.phoneTarget.value = ""
        }
        if (this.hasAddressTarget) {
            this.addressTarget.value = ""
        }
    }

    enableFields() {
        // Fields are always enabled for editing, even when a contractor is selected
        // This allows overriding contact info per-contract
    }
}
