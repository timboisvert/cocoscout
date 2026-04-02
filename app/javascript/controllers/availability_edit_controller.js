import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["readView", "editView", "link"]

    toggle(event) {
        event.preventDefault()
        this.readViewTargets.forEach(el => el.classList.toggle("hidden"))
        this.editViewTargets.forEach(el => el.classList.toggle("hidden"))
        if (this.hasLinkTarget) {
            const editing = this.editViewTargets[0] && !this.editViewTargets[0].classList.contains("hidden")
            this.linkTarget.textContent = editing ? "Done" : "Change"
        }
    }
}
