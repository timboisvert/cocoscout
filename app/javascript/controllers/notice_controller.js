import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["container"]
    static values = { timeout: Number }

    connect() {
        setTimeout(() => {
            this.dismiss()
        }, this.timeoutValue || 2000)
    }

    dismiss() {
        if (this.hasContainerTarget) {
            this.containerTarget.classList.add("-translate-y-20", "opacity-0")
            this.containerTarget.classList.remove("top-4")
            setTimeout(() => {
                this.containerTarget.remove()
            }, 300)
        }
    }
}
