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
                // A trigger inside one modal (data-modal-close-id) swaps to this one
                // instead of stacking: the first hides and comes back when this one
                // closes. Its form, if it has one, learns which modal to reopen.
                const closeId = event.currentTarget.dataset.modalCloseId
                const from = closeId ? document.getElementById(closeId) : null
                if (from) {
                    from.classList.add('hidden')
                    modal.dataset.modalReturnTo = closeId
                    modal.querySelectorAll('input[name="reopen"]').forEach(input => { input.value = closeId })
                }
                // Opened from a row inside a sheet (a ⋯ menu's item): that
                // sheet has done its job, so it goes rather than sit under
                // the new one.
                const sheet = event.currentTarget.closest('[data-sheet]')
                if (sheet && sheet !== modal) sheet.classList.add('hidden')
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
        // If controller is on the modal itself, close this.element
        // Otherwise, close the currentModal or fallback to imageModal
        const modal = this.currentModal || (this.element.id ? this.element : document.getElementById('imageModal'))
        if (modal) {
            modal.classList.add('hidden')
            document.removeEventListener('keydown', this.keyHandler)
            this.currentModal = null
            const back = modal.dataset.modalReturnTo
            if (back) {
                delete modal.dataset.modalReturnTo
                modal.querySelectorAll('input[name="reopen"]').forEach(input => { input.value = "" })
                document.getElementById(back)?.classList.remove('hidden')
            }
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
