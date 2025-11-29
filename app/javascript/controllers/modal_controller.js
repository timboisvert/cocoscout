import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["trigger"]

    connect() {
        this.keyHandler = this.handleKeydown.bind(this)
    }

    disconnect() {
        document.removeEventListener('keydown', this.keyHandler)
    }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            this.close()
        }
    }

    open(event) {
        event.preventDefault()
        const imageUrl = event.currentTarget.dataset.modalImageParam || event.currentTarget.src
        const modal = document.getElementById('imageModal')
        const modalImage = document.getElementById('modalImage')

        if (modal && modalImage && imageUrl) {
            modalImage.src = imageUrl
            modal.classList.remove('hidden')
            document.addEventListener('keydown', this.keyHandler)
        }
    }

    close(event) {
        const modal = document.getElementById('imageModal')
        if (modal) {
            modal.classList.add('hidden')
            document.removeEventListener('keydown', this.keyHandler)
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }
}
