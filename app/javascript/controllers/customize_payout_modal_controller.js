import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    close() {
        const frame = document.getElementById('customize_modal')
        if (frame) {
            frame.innerHTML = ''
        }
    }

    closeOnBackdrop(event) {
        if (event.target === this.element) {
            this.close()
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }
}
