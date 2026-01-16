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

        // Check if we have a modal ID parameter for generic modals
        const modalId = event.currentTarget.dataset.modalId
        if (modalId) {
            const modal = document.getElementById(modalId)
            if (modal) {
                modal.classList.remove('hidden')
                document.addEventListener('keydown', this.keyHandler)
                this.currentModal = modal
            }
            return
        }

        // Legacy image modal behavior
        const imageUrl = event.currentTarget.dataset.modalImageParam || event.currentTarget.src
        const modal = document.getElementById('imageModal')
        const modalImage = document.getElementById('modalImage')

        if (modal && modalImage && imageUrl) {
            modalImage.src = imageUrl
            modal.classList.remove('hidden')
            document.addEventListener('keydown', this.keyHandler)
            this.currentModal = modal
        }
    }

    close(event) {
        // Close the current modal or fallback to imageModal
        const modal = this.currentModal || document.getElementById('imageModal')
        if (modal) {
            modal.classList.add('hidden')
            document.removeEventListener('keydown', this.keyHandler)
            this.currentModal = null
        }
    }

    closeOnBackdrop(event) {
        // Only close if clicking the backdrop itself, not the modal content
        if (event.target === event.currentTarget) {
            this.close(event)
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }
}
