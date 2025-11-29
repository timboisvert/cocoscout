import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["inviteModal"]

    openInviteModal(event) {
        event.preventDefault()
        this.inviteModalTarget.classList.remove("hidden")
    }

    closeModal(event) {
        if (event.target === event.currentTarget) {
            this.inviteModalTarget.classList.add("hidden")
        }
    }

    closeInviteModal(event) {
        event.preventDefault()
        this.inviteModalTarget.classList.add("hidden")
    }

    stopPropagation(event) {
        event.stopPropagation()
    }
}
