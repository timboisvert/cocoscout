import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["input", "clearBtn"]

    connect() {
        this.toggleClear()
    }

    toggleClear() {
        if (this.hasInputTarget && this.hasClearBtnTarget) {
            if (this.inputTarget.value.length > 0) {
                this.clearBtnTarget.classList.remove("hidden")
            } else {
                this.clearBtnTarget.classList.add("hidden")
            }
        }
    }

    clear(event) {
        if (event) event.preventDefault()
        if (this.hasInputTarget) {
            this.inputTarget.value = ""
        }
        if (this.hasClearBtnTarget) {
            this.clearBtnTarget.classList.add("hidden")
        }
        // Find and submit the parent form
        const form = this.element.closest("form")
        if (form) {
            form.requestSubmit()
        }
    }

    submit(event) {
        // Prevent default enter key behavior and submit the form
        event.preventDefault()
        const form = this.element.closest("form")
        if (form) {
            form.requestSubmit()
        }
    }
}
