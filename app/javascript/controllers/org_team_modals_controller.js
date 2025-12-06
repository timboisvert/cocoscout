import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["inviteModal"]

    connect() {
        this.escapeListener = (e) => {
            if (e.key === "Escape") {
                this.closeInviteModal()
            }
        }
        document.addEventListener("keydown", this.escapeListener)
    }

    disconnect() {
        document.removeEventListener("keydown", this.escapeListener)
    }

    openInviteModal(event) {
        event.preventDefault()
        if (this.hasInviteModalTarget) {
            this.inviteModalTarget.classList.remove("hidden")
        }
    }

    closeInviteModal(event) {
        if (event) {
            event.preventDefault()
        }
        if (this.hasInviteModalTarget) {
            this.inviteModalTarget.classList.add("hidden")
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }
}
