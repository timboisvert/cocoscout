import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = {
        cycleId: Number,
        enabled: Boolean,
        url: String,
        votingType: { type: String, default: "request" }
    }

    confirm(event) {
        const checkbox = event.target
        const willEnable = checkbox.checked

        // Revert the checkbox state immediately (we'll change it after confirmation)
        checkbox.checked = !willEnable

        const action = willEnable ? 'enable' : 'disable'
        const isAudition = this.votingTypeValue === "audition"
        const message = willEnable
            ? `Are you sure you want to enable voting? Reviewers will be able to vote on ${isAudition ? 'auditions' : 'audition sign-ups'}.`
            : `Are you sure you want to disable voting? This will hide the voting interface from all reviewers.`

        if (confirm(message)) {
            // User confirmed, proceed with the toggle
            this.toggle(willEnable)
        }
        // If user cancels, checkbox stays in reverted state (original state)
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
