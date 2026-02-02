import { Controller } from "@hotwired/stimulus"

// Controller for the Contact Production Team modal
// Usage: data-controller="contact-production"
export default class extends Controller {
    static targets = ["modal", "form", "subject", "body", "submitButton", "productionName"]
    static values = {
        productionId: Number,
        productionName: String,
        showId: Number
    }

    connect() {
        this.keyHandler = this.handleKeydown.bind(this)
        this.customOpenHandler = this.handleCustomOpen.bind(this)

        // Listen for custom open events from production-select controller
        this.element.addEventListener('contact-production:open', this.customOpenHandler)
    }

    disconnect() {
        document.removeEventListener('keydown', this.keyHandler)
        this.element.removeEventListener('contact-production:open', this.customOpenHandler)
    }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            this.close()
        }
    }

    handleCustomOpen(event) {
        const { productionId, productionName, showId } = event.detail
        this.productionIdValue = parseInt(productionId)
        this.productionNameValue = productionName
        if (showId) {
            this.showIdValue = parseInt(showId)
        }
        this.openModal()
    }

    open(event) {
        event.preventDefault()

        // Get production info from the trigger button if provided
        const trigger = event.currentTarget
        if (trigger.dataset.productionId) {
            this.productionIdValue = parseInt(trigger.dataset.productionId)
        }
        if (trigger.dataset.productionName) {
            this.productionNameValue = trigger.dataset.productionName
        }
        if (trigger.dataset.showId) {
            this.showIdValue = parseInt(trigger.dataset.showId)
        }

        this.openModal()
    }

    openModal() {
        // Update the modal with production name
        if (this.hasProductionNameTarget) {
            this.productionNameTarget.textContent = this.productionNameValue
        }

        // Update form action
        if (this.hasFormTarget && this.productionIdValue) {
            this.formTarget.action = `/my/productions/${this.productionIdValue}/production_messages`
        }

        // Show modal
        if (this.hasModalTarget) {
            this.modalTarget.classList.remove('hidden')
            document.addEventListener('keydown', this.keyHandler)
            document.body.classList.add('overflow-hidden')

            // Focus the subject field
            if (this.hasSubjectTarget) {
                setTimeout(() => this.subjectTarget.focus(), 100)
            }
        }
    }

    close() {
        if (this.hasModalTarget) {
            this.modalTarget.classList.add('hidden')
            document.removeEventListener('keydown', this.keyHandler)
            document.body.classList.remove('overflow-hidden')

            // Reset form
            if (this.hasFormTarget) {
                this.formTarget.reset()
            }
        }
    }

    closeOnBackdrop(event) {
        if (event.target === event.currentTarget) {
            this.close()
        }
    }

    submit(event) {
        // Validate before submit
        if (this.hasSubjectTarget && this.hasBodyTarget) {
            const subject = this.subjectTarget.value.trim()
            const body = this.bodyTarget.value.trim()

            if (!subject || !body) {
                event.preventDefault()
                alert('Please fill in both the subject and message.')
                return
            }
        }

        // Show loading state
        if (this.hasSubmitButtonTarget) {
            this.submitButtonTarget.disabled = true
            this.submitButtonTarget.textContent = 'Sending...'
        }
    }
}
