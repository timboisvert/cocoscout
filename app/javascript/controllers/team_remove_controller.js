import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["removeButton", "row"]

    remove(event) {
        event.preventDefault()
        const button = event.currentTarget
        const url = button.dataset.url
        const token = document.querySelector('meta[name="csrf-token"]').getAttribute('content')

        if (!confirm("Are you sure you want to remove this team member?")) return

        fetch(url, {
            method: 'DELETE',
            headers: {
                'X-CSRF-Token': token,
                'Accept': 'application/json'
            }
        })
            .then(response => {
                if (!response.ok) throw new Error('Network error')
                return response.json()
            })
            .then(() => {
                // Remove the row from the DOM
                this.rowTarget.remove()
            })
            .catch(() => {
                // Optionally show error
                alert("Failed to remove team member")
            })
    }
}
