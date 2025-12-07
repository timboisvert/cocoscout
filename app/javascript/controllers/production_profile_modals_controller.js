import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["changeUrlModal", "shareModal"]

    connect() {
        this.keyHandler = this.handleKeydown.bind(this)
    }

    disconnect() {
        document.removeEventListener('keydown', this.keyHandler)
    }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            this.closeModal()
        }
    }

    openChangeUrl(event) {
        event.preventDefault()
        this.changeUrlModalTarget.classList.remove('hidden')
        document.addEventListener('keydown', this.keyHandler)
    }

    openShare(event) {
        event.preventDefault()
        this.shareModalTarget.classList.remove('hidden')
        document.addEventListener('keydown', this.keyHandler)
    }

    closeModal() {
        if (this.hasChangeUrlModalTarget) {
            this.changeUrlModalTarget.classList.add('hidden')
        }
        if (this.hasShareModalTarget) {
            this.shareModalTarget.classList.add('hidden')
        }
        document.removeEventListener('keydown', this.keyHandler)
    }

    stopPropagation(event) {
        event.stopPropagation()
    }
}
