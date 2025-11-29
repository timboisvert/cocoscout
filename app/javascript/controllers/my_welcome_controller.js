import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    async markWelcomed(event) {
        event.preventDefault()

        const link = event.currentTarget
        const href = link.href

        // Send a request to mark the user as welcomed
        try {
            await fetch('/my/dismiss_welcome', {
                method: 'POST',
                headers: {
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
                    'Content-Type': 'application/json',
                    'X-Requested-With': 'XMLHttpRequest'
                }
            })
        } catch (error) {
            console.error('Error marking welcomed:', error)
        }

        // Now navigate to the link
        window.location.href = href
    }
}
