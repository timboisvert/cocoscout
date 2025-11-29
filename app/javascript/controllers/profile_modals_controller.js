import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["changeUrlModal", "changeGroupUrlModal", "changeEmailModal", "shareModal", "addSocialModal", "editSocialModal"]

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

    openChangeGroupUrl(event) {
        event.preventDefault()
        this.changeGroupUrlModalTarget.classList.remove('hidden')
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

    openAddSocial(event) {
        event.preventDefault()
        this.addSocialModalTarget.classList.remove('hidden')
        document.addEventListener('keydown', this.keyHandler)
    }

    openEditSocial(event) {
        event.preventDefault()
        const socialId = event.currentTarget.dataset.socialId
        const platform = event.currentTarget.dataset.socialPlatform
        const handle = event.currentTarget.dataset.socialHandle
        const name = event.currentTarget.dataset.socialName || ''

        // Populate the edit form
        document.getElementById('edit-social-id').value = socialId
        document.getElementById('edit-social-platform').value = platform
        document.getElementById('edit-social-handle').value = handle
        document.getElementById('edit-social-name').value = name

        this.editSocialModalTarget.classList.remove('hidden')
        document.addEventListener('keydown', this.keyHandler)

        // Trigger the social-form controller to update label and placeholder
        setTimeout(() => {
            const modal = this.editSocialModalTarget
            const platformSelect = modal.querySelector('[data-social-form-target="platform"]')

            if (platformSelect) {
                platformSelect.dispatchEvent(new Event('change', { bubbles: true }))
            }
        }, 0)
    }

    closeModal(event) {
        if (event) {
            event.preventDefault()
        }
        if (this.hasChangeUrlModalTarget) {
            this.changeUrlModalTarget.classList.add('hidden')
        }
        if (this.hasChangeGroupUrlModalTarget) {
            this.changeGroupUrlModalTarget.classList.add('hidden')
        }
        if (this.hasChangeEmailModalTarget) {
            this.changeEmailModalTarget.classList.add('hidden')
        }
        if (this.hasShareModalTarget) {
            this.shareModalTarget.classList.add('hidden')
        }
        if (this.hasAddSocialModalTarget) {
            this.addSocialModalTarget.classList.add('hidden')
        }
        if (this.hasEditSocialModalTarget) {
            this.editSocialModalTarget.classList.add('hidden')
        }
        document.removeEventListener('keydown', this.keyHandler)
    }

    stopPropagation(event) {
        event.stopPropagation()
    }
}
