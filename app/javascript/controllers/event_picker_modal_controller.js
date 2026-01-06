import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal"]

    open() {
        if (this.hasModalTarget) {
            this.modalTarget.classList.remove("hidden")
            document.body.classList.add("overflow-hidden")
        }
    }

    close() {
        if (this.hasModalTarget) {
            this.modalTarget.classList.add("hidden")
            document.body.classList.remove("overflow-hidden")
        }
    }

    // Close on escape key
    connect() {
        this.handleKeydown = this.handleKeydown.bind(this)
        document.addEventListener("keydown", this.handleKeydown)
    }

    disconnect() {
        document.removeEventListener("keydown", this.handleKeydown)
    }

    handleKeydown(event) {
        if (event.key === "Escape") {
            this.close()
        }
    }
}
