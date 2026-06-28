import { Controller } from "@hotwired/stimulus"

// Shows/hides the tech charge fields (rate, hours, payment method) based on
// whether we are providing the tech or the contractor brings their own.
export default class extends Controller {
    static targets = ["charges"]

    connect() {
        this.toggle()
    }

    toggle() {
        const checked = this.element.querySelector('input[name="tech_provider"]:checked')
        const provider = checked ? checked.value : "them"
        if (provider === "us") {
            this.chargesTarget.classList.remove("hidden")
        } else {
            this.chargesTarget.classList.add("hidden")
        }
    }
}
