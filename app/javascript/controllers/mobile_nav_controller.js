import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["panel"]

    connect() {
        this.open = false
    }

    toggle() {
        this.open = !this.open
        this.panelTarget.classList.toggle("hidden", !this.open)
    }
}
