import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "form", "title", "nameInput", "methodInput", "submitButton",
        "restrictedCheckbox", "eligiblePeopleSection", "personCheckbox", "searchInput",
        "quantityInput", "categorySelect", "restrictedSection"]
    static values = {
        createPath: String,
        // Act-based production: roles are acts in a lineup, and a "break"
        // category row is an intermission (no performer, no restrictions).
        actMode: Boolean
    }

    get unit() {
        return this.actModeValue ? "Act" : "Role"
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
        this.titleTarget.textContent = `Add ${this.unit}`
        this.formTarget.reset()
        this.formTarget.action = this.createPathValue || this.element.dataset.createPath
        this.methodInputTarget.value = "post"
        this.submitButtonTarget.textContent = `Add ${this.unit}`

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
        this.categoryChanged()

        this.modalTarget.classList.remove("hidden")
    }

    // Act mode: drop an intermission into the lineup — a break-category role
    // named "Intermission", ready to save.
    openForBreak(event) {
        this.openForNew(event)
        this.titleTarget.textContent = "Add intermission"
        this.submitButtonTarget.textContent = "Add intermission"
        this.nameInputTarget.value = "Intermission"
        if (this.hasCategorySelectTarget) {
            this.categorySelectTarget.value = "break"
        }
        this.categoryChanged()
    }

    openForEdit(event) {
        event.preventDefault()
        const button = event.currentTarget
        const isBreak = button.dataset.roleCategory === "break"
        this.titleTarget.textContent = isBreak ? "Edit intermission" : `Edit ${this.unit}`
        this.nameInputTarget.value = button.dataset.roleName
        this.formTarget.action = button.dataset.updatePath
        this.methodInputTarget.value = "patch"
        this.submitButtonTarget.textContent = isBreak ? "Update intermission" : `Update ${this.unit}`

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
        this.categoryChanged()

        this.modalTarget.classList.remove("hidden")
    }

    // A break takes no performer: hide the restriction controls and clear them.
    categoryChanged() {
        if (!this.hasCategorySelectTarget || !this.hasRestrictedSectionTarget) return

        const isBreak = this.categorySelectTarget.value === "break"
        this.restrictedSectionTarget.classList.toggle("hidden", isBreak)
        if (isBreak && this.hasRestrictedCheckboxTarget) {
            this.restrictedCheckboxTarget.checked = false
            this.updateEligiblePeopleVisibility()
        }
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
