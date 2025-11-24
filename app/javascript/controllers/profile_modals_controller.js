import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["changeUrlModal", "changeEmailModal", "shareModal"]

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

    openChangeEmail(event) {
        event.preventDefault()
        this.changeEmailModalTarget.classList.remove('hidden')
        document.addEventListener('keydown', this.keyHandler)
    }

    openShare(event) {
        event.preventDefault()
        this.shareModalTarget.classList.remove('hidden')
        document.addEventListener('keydown', this.keyHandler)
    }

    closeModal(event) {
        if (event) {
            event.preventDefault()
        }
        if (this.hasChangeUrlModalTarget) {
            this.changeUrlModalTarget.classList.add('hidden')
        }
        if (this.hasChangeEmailModalTarget) {
            this.changeEmailModalTarget.classList.add('hidden')
        }
        if (this.hasShareModalTarget) {
            this.shareModalTarget.classList.add('hidden')
        }
        document.removeEventListener('keydown', this.keyHandler)
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    copyUrl(event) {
        event.preventDefault()
        const url = event.currentTarget.dataset.url
        navigator.clipboard.writeText(url)
        const textSpan = event.currentTarget.querySelector('.copy-text')
        if (textSpan) {
            textSpan.textContent = 'Copied!'
            setTimeout(() => textSpan.textContent = 'Copy', 2000)
        }
    }
}
