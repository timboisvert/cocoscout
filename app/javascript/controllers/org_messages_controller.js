import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    toggleProduction(event) {
        const checkbox = event.target
        const url = checkbox.dataset.url
        const enabled = checkbox.checked

        fetch(url, {
            method: 'PATCH',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
                'Accept': 'text/vnd.turbo-stream.html'
            },
            body: `forum_enabled=${enabled}`
        })
            .catch(error => {
                console.error('Error toggling production forum:', error)
                // Revert checkbox on error
                checkbox.checked = !enabled
            })
    }
}
