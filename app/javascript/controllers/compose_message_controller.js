import { Controller } from "@hotwired/stimulus"

/**
 * Unified Compose Message Controller
 *
 * Handles opening/closing a message compose modal and submitting messages
 * to various recipient types (person, group, production_team).
 *
 * Usage:
 * - Include the modal partial once per page: render "shared/compose_message_modal"
 * - Add trigger buttons with data attributes:
 *
 *   <button data-controller="compose-message"
 *           data-action="click->compose-message#open"
 *           data-compose-message-recipient-type-value="person"
 *           data-compose-message-recipient-id-value="123"
 *           data-compose-message-recipient-name-value="John Smith">
 *     Contact
 *   </button>
 */
export default class extends Controller {
    static targets = ["modal", "form", "subject", "body", "submitButton", "recipientName", "recipientType", "recipientId", "title", "recipientSection", "singleRecipient", "recipientHeadshot", "batchRecipients"]
    static values = {
        recipientType: String,  // "person", "group", "production_team", "show_cast", "batch"
        recipientId: Number,
        recipientName: String,
        recipientHeadshot: String,  // URL to headshot image
        recipientInitials: String,  // Initials if no headshot
        castMembers: Array          // Array of {name, headshot} for show_cast type
    }

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
        event?.preventDefault()

        // Get recipient info from the trigger button's data attributes if provided
        const trigger = event?.currentTarget
        if (trigger) {
            if (trigger.dataset.composeMessageRecipientTypeValue) {
                this.recipientTypeValue = trigger.dataset.composeMessageRecipientTypeValue
            }
            if (trigger.dataset.composeMessageRecipientIdValue) {
                this.recipientIdValue = parseInt(trigger.dataset.composeMessageRecipientIdValue)
            }
            if (trigger.dataset.composeMessageRecipientNameValue) {
                this.recipientNameValue = trigger.dataset.composeMessageRecipientNameValue
            }
            if (trigger.dataset.composeMessageRecipientHeadshotValue) {
                this.recipientHeadshotValue = trigger.dataset.composeMessageRecipientHeadshotValue
            }
            if (trigger.dataset.composeMessageRecipientInitialsValue) {
                this.recipientInitialsValue = trigger.dataset.composeMessageRecipientInitialsValue
            }
            if (trigger.dataset.composeMessageCastMembersValue) {
                try {
                    this.castMembersValue = JSON.parse(trigger.dataset.composeMessageCastMembersValue)
                } catch (e) {
                    this.castMembersValue = []
                }
            }
        }

        // Find the modal (it may be outside this controller's element)
        const modal = this.hasModalTarget ? this.modalTarget : document.getElementById('compose-message-modal')
        if (!modal) {
            console.error('Compose message modal not found')
            return
        }

        // Update recipient display
        this.updateRecipientDisplay(modal)

        // Set hidden form fields
        const typeInput = modal.querySelector('[data-compose-message-target="recipientType"]')
        const idInput = modal.querySelector('[data-compose-message-target="recipientId"]')
        if (typeInput) typeInput.value = this.recipientTypeValue
        if (idInput) idInput.value = this.recipientIdValue

        // Set form action based on recipient type
        const form = modal.querySelector('[data-compose-message-target="form"]')
        if (form) {
            form.action = this.getFormAction()
        }

        // Show modal
        modal.classList.remove('hidden')
        document.addEventListener('keydown', this.keyHandler)
        document.body.classList.add('overflow-hidden')

        // Focus the subject field
        const subjectInput = modal.querySelector('[data-compose-message-target="subject"]')
        if (subjectInput) {
            setTimeout(() => subjectInput.focus(), 100)
        }
    }

    updateRecipientDisplay(modal) {
        const singleRecipient = modal.querySelector('[data-compose-message-target="singleRecipient"]')
        const batchRecipients = modal.querySelector('[data-compose-message-target="batchRecipients"]')
        const nameTarget = modal.querySelector('[data-compose-message-target="recipientName"]')
        const headshotTarget = modal.querySelector('[data-compose-message-target="recipientHeadshot"]')

        // For show_cast with cast members
        if (this.recipientTypeValue === 'show_cast' && this.castMembersValue?.length > 0) {
            // If only 1 cast member, show as single recipient (no tooltip, name next to headshot)
            if (this.castMembersValue.length === 1) {
                const member = this.castMembersValue[0]
                if (singleRecipient) singleRecipient.classList.remove('hidden')
                if (batchRecipients) batchRecipients.classList.add('hidden')

                if (nameTarget) nameTarget.textContent = member.name
                if (headshotTarget) {
                    if (member.headshot) {
                        headshotTarget.innerHTML = `<img src="${member.headshot}" alt="${member.name}" class="w-8 h-8 rounded-lg object-cover ring-2 ring-white">`
                    } else {
                        const initials = this.getInitials(member.name)
                        headshotTarget.innerHTML = initials
                        headshotTarget.className = 'w-8 h-8 rounded-lg bg-pink-100 flex items-center justify-center text-pink-600 font-bold text-xs ring-2 ring-white'
                    }
                }
            } else {
                // Multiple cast members - show stacked headshots with tooltips
                if (singleRecipient) singleRecipient.classList.add('hidden')
                if (batchRecipients) {
                    batchRecipients.classList.remove('hidden')
                    batchRecipients.innerHTML = this.renderStackedHeadshots(this.castMembersValue)
                }
            }
            return
        }

        // For batch mode, the directory-selection controller handles this
        if (this.recipientTypeValue === 'batch') {
            return
        }

        // For single recipients (person, group, etc.), show single recipient display
        if (singleRecipient) singleRecipient.classList.remove('hidden')
        if (batchRecipients) batchRecipients.classList.add('hidden')

        // Update name
        if (nameTarget) {
            nameTarget.textContent = this.recipientNameValue || 'Unknown'
        }

        // Update headshot
        if (headshotTarget) {
            if (this.recipientHeadshotValue) {
                headshotTarget.innerHTML = `<img src="${this.recipientHeadshotValue}" alt="${this.recipientNameValue}" class="w-8 h-8 rounded-lg object-cover ring-2 ring-white">`
            } else {
                const initials = this.recipientInitialsValue || this.getInitials(this.recipientNameValue)
                headshotTarget.innerHTML = initials
                headshotTarget.className = 'w-8 h-8 rounded-lg bg-pink-100 flex items-center justify-center text-pink-600 font-bold text-xs ring-2 ring-white'
            }
        }
    }

    renderStackedHeadshots(members) {
        const maxVisible = 8
        const visibleMembers = members.slice(0, maxVisible)
        const overflowCount = members.length - maxVisible

        let html = visibleMembers.map(member => {
            const initials = member.name ? member.name.split(' ').map(n => n[0]).join('').toUpperCase().substring(0, 2) : '?'
            const headshot = member.headshot

            if (headshot) {
                return `
                    <span data-controller="tooltip" data-tooltip-text-value="${member.name}" class="relative">
                        <img src="${headshot}" alt="${member.name}"
                             class="w-8 h-8 rounded-lg object-cover ring-2 ring-white relative z-10 hover:z-20 hover:scale-110 transition-transform cursor-default">
                    </span>`
            } else {
                return `
                    <span data-controller="tooltip" data-tooltip-text-value="${member.name}" class="relative">
                        <div class="w-8 h-8 rounded-lg bg-pink-100 flex items-center justify-center text-pink-600 font-bold text-xs ring-2 ring-white relative z-10 hover:z-20 hover:scale-110 transition-transform cursor-default">
                            ${initials}
                        </div>
                    </span>`
            }
        }).join('')

        if (overflowCount > 0) {
            html += `
                <span data-controller="tooltip" data-tooltip-text-value="${overflowCount} more" class="relative">
                    <div class="w-8 h-8 rounded-lg bg-gray-200 flex items-center justify-center text-gray-600 font-bold text-xs ring-2 ring-white relative z-10">
                        +${overflowCount}
                    </div>
                </span>`
        }

        return html
    }

    getInitials(name) {
        if (!name) return '?'
        return name.split(' ').map(n => n[0]).join('').toUpperCase().substring(0, 2)
    }

    getFormAction() {
        // All message types now go through the unified endpoint
        return '/manage/messages'
    }

    close() {
        const modal = this.hasModalTarget ? this.modalTarget : document.getElementById('compose-message-modal')
        if (modal) {
            modal.classList.add('hidden')
            document.removeEventListener('keydown', this.keyHandler)
            document.body.classList.remove('overflow-hidden')

            // Reset form
            const form = modal.querySelector('[data-compose-message-target="form"]')
            if (form) {
                form.reset()
                // Remove any dynamically added person_ids fields (from batch mode)
                form.querySelectorAll('input[name="person_ids[]"]').forEach(el => el.remove())

                // Reset Trix editor content
                const trixEditor = form.querySelector('trix-editor')
                if (trixEditor && trixEditor.editor) {
                    trixEditor.editor.loadHTML('')
                }
            }

            // Reset title
            const titleTarget = modal.querySelector('[data-compose-message-target="title"]')
            if (titleTarget) {
                titleTarget.textContent = 'Send Message'
            }

            // Reset recipient display
            const singleRecipient = modal.querySelector('[data-compose-message-target="singleRecipient"]')
            const batchRecipients = modal.querySelector('[data-compose-message-target="batchRecipients"]')
            if (singleRecipient) singleRecipient.classList.remove('hidden')
            if (batchRecipients) {
                batchRecipients.classList.add('hidden')
                batchRecipients.innerHTML = ''
            }

            // Reset values
            this.castMembersValue = []
        }
    }

    closeOnBackdrop(event) {
        if (event.target === event.currentTarget) {
            this.close()
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    async submit(event) {
        event.preventDefault()
        event.stopPropagation()
        event.stopImmediatePropagation()

        const modal = this.hasModalTarget ? this.modalTarget : document.getElementById('compose-message-modal')
        const form = modal?.querySelector('[data-compose-message-target="form"]')
        const submitButton = modal?.querySelector('[data-compose-message-target="submitButton"]')

        if (!form) return

        // Disable button while submitting
        if (submitButton) {
            submitButton.disabled = true
            submitButton.textContent = 'Sending...'
        }

        try {
            const formData = new FormData(form)

            // Get files from image-dropzone controller if present
            const dropzoneElement = form.querySelector('[data-controller="image-dropzone"]')
            if (dropzoneElement) {
                const dropzoneController = this.application.getControllerForElementAndIdentifier(dropzoneElement, 'image-dropzone')
                if (dropzoneController && dropzoneController.files && dropzoneController.files.length > 0) {
                    // Remove any empty images entries and add our files
                    formData.delete('images[]')
                    dropzoneController.files.forEach(file => {
                        formData.append('images[]', file)
                    })
                }
            }

            const response = await fetch(form.action, {
                method: 'POST',
                body: formData,
                headers: {
                    'Accept': 'text/html, application/xhtml+xml'
                }
            })

            if (response.ok) {
                this.close()
                // Set cookie for notice since flash is consumed by fetch
                document.cookie = 'flash_notice=Message sent successfully; path=/; max-age=10'
                // Handle redirect
                if (response.redirected) {
                    window.location.href = response.url
                } else {
                    window.location.href = '/manage/messages'
                }
            } else {
                console.error('Failed to send message:', response.status)
                // Reset button on error
                if (submitButton) {
                    submitButton.disabled = false
                    submitButton.textContent = 'Send Message'
                }
            }
        } catch (error) {
            console.error('Error sending message:', error)
            if (submitButton) {
                submitButton.disabled = false
                submitButton.textContent = 'Send Message'
            }
        }
    }
}
