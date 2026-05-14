import { Controller } from "@hotwired/stimulus"

// Opens the Edit Answers form in a modal using a turbo-frame for loading.
// Usage: data-controller="edit-modal" with [data-edit-modal-target="modal"]
export default class extends Controller {
    static targets = ["modal"]

    open(event) {
        event.preventDefault()
        if (this.hasModalTarget) {
            this.modalTarget.classList.remove("hidden")
        }
    }

    close() {
        if (this.hasModalTarget) {
            this.modalTarget.classList.add("hidden")
        }
    }

    closeOnBackdrop(event) {
        if (event.target === this.modalTarget) {
            this.close()
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }
}
