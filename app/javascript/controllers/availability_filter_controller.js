import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["checkboxes", "showList", "showListToggle", "checkbox", "enableCheckbox", "eventSection", "count"]

    connect() {
        this.updateShowList()
    }

    toggleSection() {
        if (this.hasEnableCheckboxTarget && this.hasEventSectionTarget) {
            const isChecked = this.enableCheckboxTarget.checked
            if (isChecked) {
                this.eventSectionTarget.classList.remove("hidden")
            } else {
                this.eventSectionTarget.classList.add("hidden")
            }
        }
    }

    toggleShowList(event) {
        event.preventDefault()
        if (this.hasShowListTarget) {
            this.showListTarget.classList.toggle("hidden")
        }
    }

    updateFilter() {
        const allSelected = document.querySelector('input[name="show_filter_mode"][value="all"]')?.checked

        if (allSelected) {
            // Hide checkboxes
            if (this.hasCheckboxesTarget) {
                this.checkboxesTarget.classList.add("hidden")
            }
            // Uncheck all show checkboxes
            this.checkboxTargets.forEach(checkbox => {
                checkbox.checked = false
            })
            // Show the toggle button
            if (this.hasShowListToggleTarget) {
                this.showListToggleTarget.classList.remove("hidden")
            }
            // Update count to show all shows
            this.updateCount(this.getShowListItems().length)
        } else {
            // Show checkboxes
            if (this.hasCheckboxesTarget) {
                this.checkboxesTarget.classList.remove("hidden")
            }
            // Hide the toggle button
            if (this.hasShowListToggleTarget) {
                this.showListToggleTarget.classList.add("hidden")
            }
            // Hide the show list
            if (this.hasShowListTarget) {
                this.showListTarget.classList.add("hidden")
            }
            // Update show list based on checked boxes
            this.updateShowList()
        }
    }

    updateShowList() {
        const allSelected = document.querySelector('input[name="show_filter_mode"][value="all"]')?.checked

        if (allSelected) {
            // When all shows are selected, just update the count
            const showItems = this.getShowListItems()
            this.updateCount(showItems.length)
            return
        }

        // Get selected show IDs
        const selectedShowIds = this.checkboxTargets
            .filter(checkbox => checkbox.checked)
            .map(checkbox => checkbox.value)

        // Update count
        this.updateCount(selectedShowIds.length)
    }

    getShowListItems() {
        if (this.hasShowListTarget) {
            return this.showListTarget.querySelectorAll('[data-show-id]')
        }
        return []
    }

    updateCount(count) {
        if (this.hasCountTarget) {
            this.countTargets.forEach(target => {
                target.textContent = count
            })
        }
    }
}
