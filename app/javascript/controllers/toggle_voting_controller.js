import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = {
        cycleId: Number,
        enabled: Boolean,
        url: String,
        votingType: { type: String, default: "request" }
    }

    change(event) {
        const checkbox = event.target
        const willEnable = checkbox.checked

        // Revert the checkbox state immediately (we'll change it after the request)
        checkbox.checked = !willEnable

        // Proceed with the toggle directly
        this.toggle(willEnable)
    }

    async toggle(enable) {
        const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

        try {
            const response = await fetch(this.urlValue, {
                method: 'PATCH',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': csrfToken
                },
                body: JSON.stringify({
                    voting_enabled: enable,
                    voting_type: this.votingTypeValue
                })
            })

            if (response.ok) {
                // Reload the page to show updated state
                window.location.reload()
            } else {
                alert('Failed to update voting status. Please try again.')
            }
        } catch (error) {
            console.error('Error toggling voting:', error)
            alert('An error occurred. Please try again.')
        }
    }
}
