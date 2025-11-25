import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    connect() {
        this.groupId = window.location.pathname.split('/').filter(Boolean).pop()
    }

    openInviteModal(event) {
        event.preventDefault()
        // TODO: Implement invite modal if needed
        alert('Invite member functionality - to be implemented')
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
