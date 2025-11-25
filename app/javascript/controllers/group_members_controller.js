import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["inviteModal", "inviteForm"]
    static values = { groupId: String }

    connect() {
        // Fallback to extracting from URL if not provided via data attribute
        if (!this.hasGroupIdValue) {
            const pathSegments = window.location.pathname.split('/').filter(Boolean)
            // URL is /groups/:id or /groups/:id/settings
            const groupsIndex = pathSegments.indexOf('groups')
            if (groupsIndex !== -1 && pathSegments.length > groupsIndex + 1) {
                this.groupIdValue = pathSegments[groupsIndex + 1]
            }
        }
        this.keyHandler = this.handleKeydown.bind(this)
    }

    disconnect() {
        document.removeEventListener('keydown', this.keyHandler)
    }

    handleKeydown(event) {
        if (event.key === 'Escape' && this.hasInviteModalTarget && !this.inviteModalTarget.classList.contains('hidden')) {
            this.closeInviteModal()
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    openInviteModal(event) {
        event.preventDefault()
        if (this.hasInviteModalTarget) {
            this.inviteModalTarget.classList.remove('hidden')
            document.addEventListener('keydown', this.keyHandler)

            // Focus first input
            const firstInput = this.inviteModalTarget.querySelector('input[type="text"]')
            if (firstInput) {
                setTimeout(() => firstInput.focus(), 100)
            }
        }
    }

    closeInviteModal(event) {
        if (event) event.preventDefault()
        if (this.hasInviteModalTarget) {
            this.inviteModalTarget.classList.add('hidden')
            document.removeEventListener('keydown', this.keyHandler)

            // Clear form
            if (this.hasInviteFormTarget) {
                this.inviteFormTarget.reset()
            }
        }
    }

    updateRole(event) {
        const select = event.currentTarget
        const membershipId = select.dataset.membershipId
        const newRole = select.value

        fetch(`/groups/${this.groupIdValue}/update_member_role`, {
            method: 'PATCH',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
            },
            body: JSON.stringify({ membership_id: membershipId, role: newRole })
        }).then(response => {
            if (response.ok) {
                return response.json()
            } else {
                alert('Could not update role')
            }
        }).then(data => {
            if (data && data.notice) {
                this.showNotice(data.notice)
            }
        })
    }

    removeMember(event) {
        const button = event.currentTarget
        const membershipId = button.dataset.membershipId

        if (!confirm('Remove this member from the group?')) return

        fetch(`/groups/${this.groupIdValue}/remove_member`, {
            method: 'DELETE',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
            },
            body: JSON.stringify({ membership_id: membershipId })
        }).then(response => {
            if (response.ok) {
                return response.json()
            } else {
                alert('Could not remove member')
            }
        }).then(data => {
            if (data && data.notice) {
                button.closest('.flex.items-center.gap-3.p-3').remove()
                this.showNotice(data.notice)
            }
        })
    }

    updateNotifications(event) {
        const checkbox = event.currentTarget
        const membershipId = checkbox.dataset.membershipId

        fetch(`/groups/${this.groupIdValue}/update_member_notifications`, {
            method: 'PATCH',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
            },
            body: JSON.stringify({
                membership_id: membershipId,
                receives_notifications: checkbox.checked
            })
        }).then(response => {
            if (response.ok) {
                return response.json()
            } else {
                checkbox.checked = !checkbox.checked
                alert('Could not update notification settings')
            }
        }).then(data => {
            if (data && data.notice) {
                this.showNotice(data.notice)
            }
        })
    }

    showNotice(message) {
        const container = document.getElementById('notice-container')
        if (!container) return

        container.innerHTML = `
            <div data-controller="notice" data-notice-timeout-value="2000" class="fixed top-0 left-1/2 transform -translate-x-1/2 z-50 w-auto max-w-lg px-6 py-3 bg-pink-500 text-white shadow-lg flex items-center transition-opacity duration-300 rounded-bl-lg rounded-br-lg" data-notice-target="container">
                <span class="font-medium">${message}</span>
            </div>
        `
    }
}
