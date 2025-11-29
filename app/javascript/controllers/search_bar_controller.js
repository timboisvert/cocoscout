import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["input", "clearBtn", "form"]

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
        if (this.hasFormTarget) {
            this.formTarget.requestSubmit()
        }
    }
}
