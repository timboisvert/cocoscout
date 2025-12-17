import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["image", "counter", "prevButton", "nextButton", "thumbnailContainer", "thumbnail"]
    static values = {
        images: Array,
        currentIndex: { type: Number, default: 0 },
        modalId: String
    }

    connect() {
        this.keyHandler = this.handleKeydown.bind(this)
        document.addEventListener('keydown', this.keyHandler)
        this.updateDisplay()
    }

    disconnect() {
        document.removeEventListener('keydown', this.keyHandler)
    }

    handleKeydown(event) {
        // Only handle if this gallery is visible
        if (!this.element.offsetParent) return

        // Check if modal is open for this gallery
        const modal = this.getModal()
        if (modal && !modal.classList.contains('hidden')) {
            if (event.key === 'Escape') {
                event.preventDefault()
                this.closeModal()
                return
            }
        }

        if (event.key === 'ArrowLeft') {
            event.preventDefault()
            this.previous()
        } else if (event.key === 'ArrowRight') {
            event.preventDefault()
            this.next()
        }
    }

    previous() {
        if (this.currentIndexValue > 0) {
            this.currentIndexValue--
            this.updateDisplay()
        }
    }

    next() {
        if (this.currentIndexValue < this.imagesValue.length - 1) {
            this.currentIndexValue++
            this.updateDisplay()
        }
    }

    goToIndex(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10)
        if (!isNaN(index) && index >= 0 && index < this.imagesValue.length) {
            this.currentIndexValue = index
            this.updateDisplay()
        }
    }

    updateDisplay() {
        const images = this.imagesValue
        const index = this.currentIndexValue

        if (images.length === 0) return

        // Update main image
        if (this.hasImageTarget) {
            this.imageTarget.src = images[index].preview_url
            this.imageTarget.dataset.fullUrl = images[index].full_url
        }

        // Update counter
        if (this.hasCounterTarget) {
            this.counterTarget.textContent = `${index + 1} of ${images.length}`
        }

        // Update navigation button states
        if (this.hasPrevButtonTarget) {
            this.prevButtonTarget.disabled = index === 0
            this.prevButtonTarget.classList.toggle('opacity-30', index === 0)
            this.prevButtonTarget.classList.toggle('cursor-not-allowed', index === 0)
        }

        if (this.hasNextButtonTarget) {
            this.nextButtonTarget.disabled = index === images.length - 1
            this.nextButtonTarget.classList.toggle('opacity-30', index === images.length - 1)
            this.nextButtonTarget.classList.toggle('cursor-not-allowed', index === images.length - 1)
        }

        // Update thumbnail active states
        if (this.hasThumbnailTarget) {
            this.thumbnailTargets.forEach((thumb, i) => {
                thumb.classList.toggle('border-pink-500', i === index)
                thumb.classList.toggle('border-gray-200', i !== index)
                thumb.classList.toggle('opacity-100', i === index)
                thumb.classList.toggle('opacity-60', i !== index)
            })
        }
    }

    getModal() {
        if (this.hasModalIdValue) {
            return document.getElementById(this.modalIdValue)
        }
        // Fallback to global imageModal
        return document.getElementById('imageModal')
    }

    getModalImage() {
        if (this.hasModalIdValue) {
            return document.getElementById(`${this.modalIdValue}_image`)
        }
        // Fallback to global modalImage
        return document.getElementById('modalImage')
    }

    openModal() {
        const images = this.imagesValue
        const index = this.currentIndexValue

        if (images.length === 0) return

        const fullUrl = images[index].full_url
        const modal = this.getModal()
        const modalImage = this.getModalImage()

        if (modal && modalImage && fullUrl) {
            modalImage.src = fullUrl
            modal.classList.remove('hidden')
            document.body.style.overflow = 'hidden'
        }
    }

    closeModal() {
        const modal = this.getModal()
        if (modal) {
            modal.classList.add('hidden')
            document.body.style.overflow = ''
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }
}
