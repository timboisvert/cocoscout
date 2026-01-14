import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    close() {
        const frame = document.getElementById('change_scheme_modal')
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
