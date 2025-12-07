import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["inviteModal", "permissionsModal", "permissionsContent", "permissionsTitle"]

    connect() {
        this.escapeListener = (e) => {
            if (e.key === "Escape") {
                this.closeInviteModal()
                this.closePermissionsModal()
            }
        }
        document.addEventListener("keydown", this.escapeListener)
    }

    disconnect() {
        document.removeEventListener("keydown", this.escapeListener)
    }

    openInviteModal(event) {
        event.preventDefault()
        if (this.hasInviteModalTarget) {
            this.inviteModalTarget.classList.remove("hidden")
        }
    }

    closeInviteModal(event) {
        if (event) {
            event.preventDefault()
        }
        if (this.hasInviteModalTarget) {
            this.inviteModalTarget.classList.add("hidden")
        }
    }

    openPermissionsModal(event) {
        event.preventDefault()
        const memberName = event.currentTarget.dataset.memberName
        const permissionsUrl = event.currentTarget.dataset.permissionsUrl

        this.permissionsTitleTarget.textContent = `Permissions for ${memberName}`
        this.permissionsContentTarget.innerHTML = '<p class="text-gray-500 text-center py-8">Loading...</p>'
        this.permissionsModalTarget.classList.remove("hidden")

        // Fetch permissions content via AJAX
        fetch(permissionsUrl, {
            headers: {
                'Accept': 'text/html',
                'X-Requested-With': 'XMLHttpRequest'
            }
        })
            .then(response => response.text())
            .then(html => {
                this.permissionsContentTarget.innerHTML = html
            })
            .catch(error => {
                this.permissionsContentTarget.innerHTML = '<p class="text-red-500 text-center py-8">Error loading permissions</p>'
            })
    }

    closePermissionsModal(event) {
        if (event) {
            event.preventDefault()
        }
        if (this.hasPermissionsModalTarget) {
            this.permissionsModalTarget.classList.add("hidden")
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }
}
