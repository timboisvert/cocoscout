import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "editLocationModal", "addSpaceModal", "editSpaceModal",
        "editSpaceForm", "editSpaceName", "editSpaceCapacity", "editSpaceDefault"
    ]

    // Location modal
    openEditLocationModal(event) {
        event.preventDefault()
        this.editLocationModalTarget.classList.remove("hidden")
        document.body.classList.add("overflow-hidden")
    }

    closeEditLocationModal() {
        this.editLocationModalTarget.classList.add("hidden")
        document.body.classList.remove("overflow-hidden")
    }

    // Add space modal
    openAddSpaceModal(event) {
        event.preventDefault()
        this.addSpaceModalTarget.classList.remove("hidden")
        document.body.classList.add("overflow-hidden")
    }

    closeAddSpaceModal() {
        this.addSpaceModalTarget.classList.add("hidden")
        document.body.classList.remove("overflow-hidden")
    }

    // Edit space modal
    openEditSpaceModal(event) {
        event.preventDefault()
        const button = event.currentTarget
        const spaceId = button.dataset.spaceId
        const spaceName = button.dataset.spaceName
        const spaceCapacity = button.dataset.spaceCapacity
        const spaceDefault = button.dataset.spaceDefault === "true"
        const spacePath = button.dataset.spacePath

        // Populate form
        this.editSpaceFormTarget.action = spacePath
        this.editSpaceNameTarget.value = spaceName
        this.editSpaceCapacityTarget.value = spaceCapacity || ""
        this.editSpaceDefaultTarget.checked = spaceDefault

        this.editSpaceModalTarget.classList.remove("hidden")
        document.body.classList.add("overflow-hidden")
    }

    closeEditSpaceModal() {
        this.editSpaceModalTarget.classList.add("hidden")
        document.body.classList.remove("overflow-hidden")
    }

    // Close on escape
    connect() {
        this.handleKeydown = this.handleKeydown.bind(this)
        document.addEventListener("keydown", this.handleKeydown)
    }

    disconnect() {
        document.removeEventListener("keydown", this.handleKeydown)
    }

    handleKeydown(event) {
        if (event.key === "Escape") {
            if (this.hasEditLocationModalTarget && !this.editLocationModalTarget.classList.contains("hidden")) {
                this.closeEditLocationModal()
            }
            if (this.hasAddSpaceModalTarget && !this.addSpaceModalTarget.classList.contains("hidden")) {
                this.closeAddSpaceModal()
            }
            if (this.hasEditSpaceModalTarget && !this.editSpaceModalTarget.classList.contains("hidden")) {
                this.closeEditSpaceModal()
            }
        }
    }
}
