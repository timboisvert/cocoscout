import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["inviteModal", "permissionsModal", "permissionsContent", "permissionsTitle"]

    openInviteModal(event) {
        event.preventDefault()
        this.inviteModalTarget.classList.remove("hidden")
    }

    closeModal(event) {
        if (event.target === event.currentTarget) {
            this.inviteModalTarget.classList.add("hidden")
        }
    }

    closeInviteModal(event) {
        event.preventDefault()
        this.inviteModalTarget.classList.add("hidden")
    }

    openPermissionsModal(event) {
        event.preventDefault()
        const memberId = event.currentTarget.dataset.memberId
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
            if (event.target !== event.currentTarget && event.type === 'click') {
                return
            }
        }
        this.permissionsModalTarget.classList.add("hidden")
    }

    stopPropagation(event) {
        event.stopPropagation()
    }
}
