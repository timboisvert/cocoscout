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
        "editNotifications",
        "removeForm",
        "removeUserId",
        "removeUserName"
    ]

    openAddModal() {
        this.addModalTarget.classList.remove("hidden")
    }

    closeAddModal() {
        this.addModalTarget.classList.add("hidden")
    }

    openEditModal(event) {
        const userId = event.currentTarget.dataset.userId
        const userName = event.currentTarget.dataset.userName
        const role = event.currentTarget.dataset.role
        const notifications = event.currentTarget.dataset.notifications

        this.editUserIdTarget.value = userId
        this.editUserNameTarget.textContent = userName
        this.editRoleTarget.value = role
        this.editNotificationsTarget.checked = notifications === "1"

        this.editModalTarget.classList.remove("hidden")
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
