import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "form", "title", "nameInput", "methodInput", "submitButton",
        "restrictedCheckbox", "eligiblePeopleSection", "personCheckbox", "searchInput",
        "quantityInput", "categorySelect"]
    static values = {
        createPath: String
    }

    connect() {
        this.updateEligiblePeopleVisibility()
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
}
