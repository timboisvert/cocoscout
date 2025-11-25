import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["inviteModal", "inviteForm"]

    connect() {
        this.groupId = window.location.pathname.split('/').filter(Boolean).pop()
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

        fetch(`/manage/groups/${this.groupId}/update_member_role`, {
            method: 'PATCH',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
            },
            body: JSON.stringify({ person_id: membershipId, role: newRole })
        }).then(response => {
            if (!response.ok) {
                alert('Could not update role')
            }
        })
    }

    removeMember(event) {
        const button = event.currentTarget
        const membershipId = button.dataset.membershipId

        if (!confirm('Remove this member from the group?')) return

        fetch(`/manage/groups/${this.groupId}/remove_member`, {
            method: 'DELETE',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
            },
            body: JSON.stringify({ person_id: membershipId })
        }).then(response => {
            if (response.ok) {
                button.closest('.flex.items-center.gap-3.p-3').remove()
            } else {
                alert('Could not remove member')
            }
        })
    }

    updateNotifications(event) {
        const checkbox = event.currentTarget
        const membershipId = checkbox.dataset.membershipId

        fetch(`/manage/groups/${this.groupId}/update_member_notifications`, {
            method: 'PATCH',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
            },
            body: JSON.stringify({
                person_id: membershipId,
                receives_notifications: checkbox.checked
            })
        }).then(response => {
            if (!response.ok) {
                checkbox.checked = !checkbox.checked
                alert('Could not update notification settings')
            }
        })
    }
}
