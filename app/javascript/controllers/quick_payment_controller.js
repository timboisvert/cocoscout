import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["popup"]

    toggle(event) {
        event.preventDefault()
        event.stopPropagation()
        this.popupTarget.classList.toggle("hidden")

        if (!this.popupTarget.classList.contains("hidden")) {
            // Close when clicking outside
            this._closeHandler = (e) => {
                if (!this.element.contains(e.target)) {
                    this.close()
                }
            }
            document.addEventListener("click", this._closeHandler)
        }
    }

    close() {
        this.popupTarget.classList.add("hidden")
        if (this._closeHandler) {
            document.removeEventListener("click", this._closeHandler)
        }
    }

    disconnect() {
        if (this._closeHandler) {
            document.removeEventListener("click", this._closeHandler)
        }
    }
}
