import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "form", "title", "nameInput", "methodInput", "submitButton",
        "restrictedCheckbox", "eligiblePeopleSection", "personCheckbox", "searchInput",
        "quantityInput", "categorySelect", "paymentTypeSelect", "paymentFieldsSection",
        "flatRateField", "perTicketField", "minimumField",
        "paymentAmountInput", "paymentRateInput", "paymentMinimumInput"]
    static values = {
        createPath: String
    }

    connect() {
        this.updateEligiblePeopleVisibility()
        this.updatePaymentFieldsVisibility()
        this.boundHandleKeydown = this.handleKeydown.bind(this)
        document.addEventListener("keydown", this.boundHandleKeydown)
    }

    disconnect() {
        document.removeEventListener("keydown", this.boundHandleKeydown)
    }

    handleKeydown(event) {
        if (event.key === "Escape" && !this.modalTarget.classList.contains("hidden")) {
            this.modalTarget.classList.add("hidden")
        }
    }

    openForNew(event) {
        event.preventDefault()
        this.titleTarget.textContent = "Add Role"
        this.formTarget.reset()
        this.formTarget.action = this.createPathValue || this.element.dataset.createPath
        this.methodInputTarget.value = "post"
        this.submitButtonTarget.textContent = "Add Role"

        // Reset restricted toggle and people selection
        if (this.hasRestrictedCheckboxTarget) {
            this.restrictedCheckboxTarget.checked = false
        }
        this.clearPersonSelections()
        this.updateEligiblePeopleVisibility()
        this.clearSearch()

        // Reset new fields to defaults
        if (this.hasQuantityInputTarget) {
            this.quantityInputTarget.value = 1
        }
        if (this.hasCategorySelectTarget) {
            this.categorySelectTarget.value = "performing"
        }
        if (this.hasPaymentTypeSelectTarget) {
            this.paymentTypeSelectTarget.value = "non_paying"
        }
        this.clearPaymentAmounts()
        this.updatePaymentFieldsVisibility()

        this.modalTarget.classList.remove("hidden")
    }

    openForEdit(event) {
        event.preventDefault()
        const button = event.currentTarget
        this.titleTarget.textContent = "Edit Role"
        this.nameInputTarget.value = button.dataset.roleName
        this.formTarget.action = button.dataset.updatePath
        this.methodInputTarget.value = "patch"
        this.submitButtonTarget.textContent = "Update Role"

        // Set restricted toggle and load eligible members
        if (this.hasRestrictedCheckboxTarget) {
            const isRestricted = button.dataset.roleRestricted === "true"
            this.restrictedCheckboxTarget.checked = isRestricted

            // Pre-select eligible members (format: "Type_ID")
            this.clearPersonSelections()
            const eligibleMemberKeys = JSON.parse(button.dataset.eligibleMemberKeys || "[]")
            this.personCheckboxTargets.forEach(checkbox => {
                checkbox.checked = eligibleMemberKeys.includes(checkbox.value)
            })
        }
        this.updateEligiblePeopleVisibility()
        this.clearSearch()

        // Set new fields from data attributes
        if (this.hasQuantityInputTarget) {
            this.quantityInputTarget.value = button.dataset.roleQuantity || 1
        }
        if (this.hasCategorySelectTarget) {
            this.categorySelectTarget.value = button.dataset.roleCategory || "performing"
        }
        if (this.hasPaymentTypeSelectTarget) {
            this.paymentTypeSelectTarget.value = button.dataset.rolePaymentType || "non_paying"
        }
        if (this.hasPaymentAmountInputTarget) {
            this.paymentAmountInputTarget.value = button.dataset.rolePaymentAmount || ""
        }
        if (this.hasPaymentRateInputTarget) {
            this.paymentRateInputTarget.value = button.dataset.rolePaymentRate || ""
        }
        if (this.hasPaymentMinimumInputTarget) {
            this.paymentMinimumInputTarget.value = button.dataset.rolePaymentMinimum || ""
        }
        this.updatePaymentFieldsVisibility()

        this.modalTarget.classList.remove("hidden")
    }

    toggleRestricted() {
        this.updateEligiblePeopleVisibility()
    }

    updateEligiblePeopleVisibility() {
        if (!this.hasEligiblePeopleSectionTarget || !this.hasRestrictedCheckboxTarget) return

        if (this.restrictedCheckboxTarget.checked) {
            this.eligiblePeopleSectionTarget.classList.remove("hidden")
        } else {
            this.eligiblePeopleSectionTarget.classList.add("hidden")
            this.clearPersonSelections()
        }
    }

    clearPersonSelections() {
        this.personCheckboxTargets.forEach(checkbox => {
            checkbox.checked = false
        })
    }

    filterPeople() {
        if (!this.hasSearchInputTarget) return

        const query = this.searchInputTarget.value.toLowerCase()
        const personItems = this.eligiblePeopleSectionTarget.querySelectorAll("[data-person-name]")

        personItems.forEach(item => {
            const name = item.dataset.personName.toLowerCase()
            if (query === "" || name.includes(query)) {
                item.classList.remove("hidden")
            } else {
                item.classList.add("hidden")
            }
        })
    }

    clearSearch() {
        if (this.hasSearchInputTarget) {
            this.searchInputTarget.value = ""
            this.filterPeople()
        }
    }

    close(event) {
        if (event) {
            if (event.target === this.modalTarget || event.currentTarget.dataset.action?.includes("close")) {
                this.modalTarget.classList.add("hidden")
            }
        } else {
            this.modalTarget.classList.add("hidden")
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    // Payment fields handling
    togglePaymentFields() {
        this.updatePaymentFieldsVisibility()
    }

    updatePaymentFieldsVisibility() {
        if (!this.hasPaymentTypeSelectTarget || !this.hasPaymentFieldsSectionTarget) return

        const paymentType = this.paymentTypeSelectTarget.value

        // Hide all payment fields first
        this.paymentFieldsSectionTarget.classList.add("hidden")
        if (this.hasFlatRateFieldTarget) this.flatRateFieldTarget.classList.add("hidden")
        if (this.hasPerTicketFieldTarget) this.perTicketFieldTarget.classList.add("hidden")
        if (this.hasMinimumFieldTarget) this.minimumFieldTarget.classList.add("hidden")

        // Show relevant fields based on payment type
        if (paymentType === "flat_rate") {
            this.paymentFieldsSectionTarget.classList.remove("hidden")
            if (this.hasFlatRateFieldTarget) this.flatRateFieldTarget.classList.remove("hidden")
        } else if (paymentType === "per_ticket") {
            this.paymentFieldsSectionTarget.classList.remove("hidden")
            if (this.hasPerTicketFieldTarget) this.perTicketFieldTarget.classList.remove("hidden")
        } else if (paymentType === "per_ticket_with_minimum") {
            this.paymentFieldsSectionTarget.classList.remove("hidden")
            if (this.hasPerTicketFieldTarget) this.perTicketFieldTarget.classList.remove("hidden")
            if (this.hasMinimumFieldTarget) this.minimumFieldTarget.classList.remove("hidden")
        }
    }

    clearPaymentAmounts() {
        if (this.hasPaymentAmountInputTarget) this.paymentAmountInputTarget.value = ""
        if (this.hasPaymentRateInputTarget) this.paymentRateInputTarget.value = ""
        if (this.hasPaymentMinimumInputTarget) this.paymentMinimumInputTarget.value = ""
    }
}
