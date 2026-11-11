import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "addModal",
        "editModal",
        "removeModal",
        "editForm",
        "editUserId",
        "editUserName",
        "editRole",
        "editRoleSection",
        "editOrgRoleSection",
        "editOrgRole",
        "editNotifications",
        "editRemove",
        "removeForm",
        "removeUserId",
        "removeUserName"
    ]

    openAddModal() {
        this.addModalTarget.classList.remove("hidden")
        // Reset the search controller inside the modal
        const searchController = this.application.getControllerForElementAndIdentifier(
            this.addModalTarget.querySelector('[data-controller="production-team-search"]'),
            "production-team-search"
        )
        if (searchController) searchController.reset()
    }

    closeAddModal() {
        this.addModalTarget.classList.add("hidden")
    }

    // One modal for a person's tile: their role here (the production's own
    // team only; an organization manager's role is the organization's) and
    // whether this production notifies them.
    openEditModal(event) {
        const data = event.currentTarget.dataset
        const onTeam = data.onTeam === "true"

        this.editUserIdTarget.value = data.userId
        this.editUserNameTarget.textContent = data.userName
        this.editNotificationsTarget.checked = data.notified === "true"

        this.editRoleSectionTarget.classList.toggle("hidden", !onTeam)
        this.editRoleTarget.disabled = !onTeam
        if (onTeam) this.editRoleTarget.value = data.role
        this.editOrgRoleSectionTarget.classList.toggle("hidden", onTeam)
        this.editOrgRoleTarget.textContent = data.roleLabel
        this.editRemoveTarget.classList.toggle("hidden", !onTeam)

        this.editModalTarget.classList.remove("hidden")
    }

    // Remove, from inside the edit modal: the same confirmation as before.
    removeFromEdit() {
        this.removeUserIdTarget.value = this.editUserIdTarget.value
        this.removeUserNameTarget.textContent = this.editUserNameTarget.textContent
        this.closeEditModal()
        this.removeModalTarget.classList.remove("hidden")
    }

    closeEditModal() {
        this.editModalTarget.classList.add("hidden")
    }

    confirmRemove(event) {
        const userId = event.currentTarget.dataset.userId
        const userName = event.currentTarget.dataset.userName

        this.removeUserIdTarget.value = userId
        this.removeUserNameTarget.textContent = userName

        this.removeModalTarget.classList.remove("hidden")
    }

    closeRemoveModal() {
        this.removeModalTarget.classList.add("hidden")
    }

    stopPropagation(event) {
        event.stopPropagation()
    }
}
