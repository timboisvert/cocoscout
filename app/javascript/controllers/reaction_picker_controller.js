import { Controller } from "@hotwired/stimulus"

// Handles the emoji reaction picker dropdown
export default class extends Controller {
    static targets = ["dropdown"]
    static values = { messageId: Number }

    connect() {
        // Close dropdown when clicking outside
        this.handleClickOutside = this.handleClickOutside.bind(this)
        document.addEventListener("click", this.handleClickOutside)
    }

    disconnect() {
        document.removeEventListener("click", this.handleClickOutside)
    }

    toggle(event) {
        event.stopPropagation()
        if (this.hasDropdownTarget) {
            this.dropdownTarget.classList.toggle("hidden")
        }
    }

    close() {
        if (this.hasDropdownTarget) {
            this.dropdownTarget.classList.add("hidden")
        }
    }

    handleClickOutside(event) {
        if (!this.element.contains(event.target)) {
            this.close()
        }
    }
}
