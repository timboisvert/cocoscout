import { Controller } from "@hotwired/stimulus"
import { confirmDialog } from "controllers/lib/confirm_dialog"

export default class extends Controller {
    static targets = ["removeButton", "row"]

    async remove(event) {
        event.preventDefault()
        const button = event.currentTarget
        const url = button.dataset.url
        const token = document.querySelector('meta[name="csrf-token"]').getAttribute('content')

        if (!(await confirmDialog({ title: "Remove team member?", message: "Are you sure you want to remove this team member?", confirmText: "Remove" }))) return

        fetch(url, {
            method: 'DELETE',
            headers: {
                'X-CSRF-Token': token,
                'Accept': 'application/json',
                'X-Requested-With': 'XMLHttpRequest'
            }
        })
            .then(response => {
                if (!response.ok) throw new Error('Network error')
                return response.json()
            })
            .then(() => {
                // If there's a row target, remove it (on index page)
                // Otherwise redirect to team page (on permissions page)
                if (this.hasRowTarget) {
                    this.rowTarget.remove()
                } else {
                    window.location.href = '/manage/team'
                }
            })
            .catch(() => {
                // Optionally show error
                alert("Failed to remove team member")
            })
    }
}
