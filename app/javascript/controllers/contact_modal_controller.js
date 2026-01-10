import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    close() {
        // Clear the turbo frame content to close the modal
        const frame = document.getElementById('contact_modal')
        if (frame) {
            frame.innerHTML = ''
        }
    }

    closeOnBackdrop(event) {
        // Only close if clicking the backdrop itself
        if (event.target === this.element) {
            this.close()
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }
}
