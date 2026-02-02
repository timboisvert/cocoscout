import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "modalContent"]

    connect() {
        // Auto-show modal when the turbo frame loads
        if (this.hasModalTarget) {
            this.openModal()
        }
    }

    openModal() {
        if (this.hasModalTarget) {
            this.modalTarget.classList.remove('hidden')
        }
    }

    closeModal() {
        if (this.hasModalTarget) {
            this.modalTarget.classList.add('hidden')
        }
    }

    closeModalOnBackdrop(event) {
        if (event.target === this.modalTarget) {
            this.closeModal()
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }
}
