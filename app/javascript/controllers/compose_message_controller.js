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
    static targets = ["modal", "form", "subject", "body", "submitButton", "recipientName", "recipientType", "recipientId", "title", "recipientSection", "singleRecipient", "recipientHeadshot", "batchRecipients", "sendSeparatelySection", "sendSeparately"]
    static values = {
        recipientType: String,  // "person", "group", "production_team", "show_cast", "batch", "talent_pool"
        recipientId: Number,
        recipientName: String,
        recipientHeadshot: String,  // URL to headshot image
        recipientInitials: String,  // Initials if no headshot
        castMembers: Array,          // Array of {name, headshot} for show_cast type
        batchPersonIds: Array,       // Array of person IDs for batch mode
        scriptId: String,            // ID of script tag containing ALL data as JSON
        productionId: Number         // Production ID for talent_pool messages
    }

    connect() {
        this.keyHandler = this.handleKeydown.bind(this)
        this.templateSubjectValue = ''
        this.templateBodyValue = ''
    }

    disconnect() {
        document.removeEventListener('keydown', this.keyHandler)
    }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            this.close()
        }
    }

    // New method that loads ALL data from a script tag - no data attributes needed
    openFromScript(event) {
        event?.preventDefault()

        const scriptId = this.scriptIdValue
        if (!scriptId) {
            console.error('No script ID provided')
            return
        }

        const scriptTag = document.getElementById(scriptId)
        if (!scriptTag) {
            console.error('Script tag not found:', scriptId)
            return
        }

        let data
        try {
            data = JSON.parse(scriptTag.textContent)
        } catch (e) {
            console.error('Failed to parse script data:', e)
            return
        }

        // Set all values from the script data
        this.recipientTypeValue = data.recipientType || ''
        this.recipientNameValue = data.recipientName || ''
        this.castMembersValue = data.castMembers || []
        this.batchPersonIdsValue = data.batchPersonIds || []
        this.templateSubjectValue = data.templateSubject || ''
        this.templateBodyValue = data.templateBody || ''

        // Now open the modal with all the data loaded
        this._openModal()
    }

    open(event) {
        event?.preventDefault()

        // Get recipient info from the trigger button's data attributes if provided
        // Check both the trigger element AND this.element (controller element) since
        // the data may be on either one depending on how the button is structured
        const trigger = event?.currentTarget
        const sources = [trigger, this.element].filter(Boolean)

        // Reset template values before reading new ones
        this.templateSubjectValue = ''
        this.templateBodyValue = ''
        this.templateDataIdValue = ''

        for (const source of sources) {
            if (source.dataset.composeMessageRecipientTypeValue && !this.recipientTypeValue) {
                this.recipientTypeValue = source.dataset.composeMessageRecipientTypeValue
            }
            if (source.dataset.composeMessageRecipientIdValue && !this.recipientIdValue) {
                this.recipientIdValue = parseInt(source.dataset.composeMessageRecipientIdValue)
            }
            if (source.dataset.composeMessageRecipientNameValue && !this.recipientNameValue) {
                this.recipientNameValue = source.dataset.composeMessageRecipientNameValue
            }
            if (source.dataset.composeMessageRecipientHeadshotValue && !this.recipientHeadshotValue) {
                this.recipientHeadshotValue = source.dataset.composeMessageRecipientHeadshotValue
            }
            if (source.dataset.composeMessageRecipientInitialsValue && !this.recipientInitialsValue) {
                this.recipientInitialsValue = source.dataset.composeMessageRecipientInitialsValue
            }
            if (source.dataset.composeMessageCastMembersValue && (!this.castMembersValue || this.castMembersValue.length === 0)) {
                try {
                    this.castMembersValue = JSON.parse(source.dataset.composeMessageCastMembersValue)
                } catch (e) {
                    this.castMembersValue = []
                }
            }
            if (source.dataset.composeMessageBatchPersonIdsValue && (!this.batchPersonIdsValue || this.batchPersonIdsValue.length === 0)) {
                try {
                    this.batchPersonIdsValue = JSON.parse(source.dataset.composeMessageBatchPersonIdsValue)
                } catch (e) {
                    this.batchPersonIdsValue = []
                }
            }
            if (source.dataset.composeMessageTemplateDataIdValue && !this.templateDataIdValue) {
                this.templateDataIdValue = source.dataset.composeMessageTemplateDataIdValue
            }
            if (source.dataset.composeMessageProductionIdValue && !this.productionIdValue) {
                this.productionIdValue = parseInt(source.dataset.composeMessageProductionIdValue)
            }
        }

        // Load template data from script tag if specified
        if (this.templateDataIdValue) {
            const scriptTag = document.getElementById(this.templateDataIdValue)
            if (scriptTag) {
                try {
                    const templateData = JSON.parse(scriptTag.textContent)
                    this.templateSubjectValue = templateData.subject || ''
                    this.templateBodyValue = templateData.body || ''
                } catch (e) {
                    console.error('Failed to parse template data:', e)
                }
            }
        }

        this._openModal()
    }

    _openModal() {
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

        // Handle batch person IDs and production_id field
        const form = modal.querySelector('[data-compose-message-target="form"]')
        if (form) {
            form.querySelectorAll('input[name="person_ids[]"]').forEach(el => el.remove())
            form.querySelectorAll('input[name="production_id"]').forEach(el => el.remove())

            // Add new person_ids for batch mode
            if (this.recipientTypeValue === 'batch' && this.batchPersonIdsValue?.length > 0) {
                this.batchPersonIdsValue.forEach(id => {
                    const input = document.createElement('input')
                    input.type = 'hidden'
                    input.name = 'person_ids[]'
                    input.value = id
                    form.appendChild(input)
                })
            }

            // Add production_id for talent_pool messages
            if (this.recipientTypeValue === 'talent_pool' && this.productionIdValue) {
                const input = document.createElement('input')
                input.type = 'hidden'
                input.name = 'production_id'
                input.value = this.productionIdValue
                form.appendChild(input)
            }

            form.action = this.getFormAction()
        }

        // Show/hide send separately section based on recipient type
        const sendSeparatelySection = modal.querySelector('[data-compose-message-target="sendSeparatelySection"]')
        const sendSeparatelyCheckbox = modal.querySelector('[data-compose-message-target="sendSeparately"]')
        if (sendSeparatelySection) {
            const isBatchOrMultiple = this.recipientTypeValue === 'batch' ||
                (this.recipientTypeValue === 'show_cast' && this.castMembersValue?.length > 1)
            if (isBatchOrMultiple) {
                sendSeparatelySection.classList.remove('hidden')
            } else {
                sendSeparatelySection.classList.add('hidden')
            }
            // Reset the checkbox
            if (sendSeparatelyCheckbox) {
                sendSeparatelyCheckbox.checked = false
            }
        }

        // Calculate and store recipient count for use in toggleSendSeparately
        const recipientCount = this.batchPersonIdsValue?.length || this.castMembersValue?.length || 1
        modal.dataset.recipientCount = recipientCount

        // Reset submit button text
        const submitButton = modal.querySelector('[data-compose-message-target="submitButton"]')
        if (submitButton) {
            const textTarget = submitButton.querySelector('span') || submitButton
            if (recipientCount > 1) {
                textTarget.textContent = `Send to ${recipientCount} People`
            } else {
                textTarget.textContent = 'Send Message'
            }
        }

        // Pre-fill subject and body from template if provided
        const subjectInput = modal.querySelector('[data-compose-message-target="subject"]')
        const bodyInput = modal.querySelector('trix-editor')

        if (subjectInput && this.templateSubjectValue) {
            subjectInput.value = this.templateSubjectValue
        }

        if (bodyInput && this.templateBodyValue) {
            // Convert simple markdown to HTML for Trix
            const html = this.markdownToHtml(this.templateBodyValue)
            bodyInput.editor.loadHTML(html)
        }

        // Show modal
        modal.classList.remove('hidden')
        document.addEventListener('keydown', this.keyHandler)
        document.body.classList.add('overflow-hidden')

        // Focus the subject field
        if (subjectInput) {
            setTimeout(() => subjectInput.focus(), 100)
        }
    }

    updateRecipientDisplay(modal) {
        const singleRecipient = modal.querySelector('[data-compose-message-target="singleRecipient"]')
        const batchRecipients = modal.querySelector('[data-compose-message-target="batchRecipients"]')
        const nameTarget = modal.querySelector('[data-compose-message-target="recipientName"]')
        const headshotTarget = modal.querySelector('[data-compose-message-target="recipientHeadshot"]')

        // For show_cast or talent_pool with cast members
        if ((this.recipientTypeValue === 'show_cast' || this.recipientTypeValue === 'talent_pool') && this.castMembersValue?.length > 0) {
            // If only 1 member, show as single recipient (no tooltip, name next to headshot)
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
                // Multiple members - show stacked headshots with tooltips
                if (singleRecipient) singleRecipient.classList.add('hidden')
                if (batchRecipients) {
                    batchRecipients.classList.remove('hidden')
                    batchRecipients.innerHTML = this.renderStackedHeadshots(this.castMembersValue)
                }
            }
            return
        }

        // For batch mode with cast members data, show stacked headshots
        if (this.recipientTypeValue === 'batch' && this.castMembersValue?.length > 0) {
            if (singleRecipient) singleRecipient.classList.add('hidden')
            if (batchRecipients) {
                batchRecipients.classList.remove('hidden')
                batchRecipients.innerHTML = this.renderStackedHeadshots(this.castMembersValue)
            }
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

    toggleSendSeparately(event) {
        const modal = this.hasModalTarget ? this.modalTarget : document.getElementById('compose-message-modal')
        const submitButton = modal?.querySelector('[data-compose-message-target="submitButton"]')
        const isChecked = event.target.checked

        if (submitButton && modal) {
            // Get recipient count from data attribute stored when modal opened
            const recipientCount = parseInt(modal.dataset.recipientCount) || 1
            const textTarget = submitButton.querySelector('span') || submitButton
            if (isChecked && recipientCount > 1) {
                textTarget.textContent = `Send to ${recipientCount} People Separately`
            } else if (recipientCount > 1) {
                textTarget.textContent = `Send to ${recipientCount} People`
            } else {
                textTarget.textContent = 'Send Message'
            }
        }
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

            // Reset send separately section
            const sendSeparatelySection = modal.querySelector('[data-compose-message-target="sendSeparatelySection"]')
            const sendSeparatelyCheckbox = modal.querySelector('[data-compose-message-target="sendSeparately"]')
            if (sendSeparatelySection) {
                sendSeparatelySection.classList.add('hidden')
            }
            if (sendSeparatelyCheckbox) {
                sendSeparatelyCheckbox.checked = false
            }

            // Reset submit button text
            const submitButton = modal.querySelector('[data-compose-message-target="submitButton"]')
            if (submitButton) {
                submitButton.textContent = 'Send Message'
                submitButton.disabled = false
            }

            // Reset values
            this.castMembersValue = []
            this.batchPersonIdsValue = []
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

    // Convert simple markdown to HTML for Trix editor
    markdownToHtml(text) {
        if (!text) return ''

        return text
            // Convert **bold** to <strong>
            .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
            // Convert *italic* to <em>
            .replace(/\*(.+?)\*/g, '<em>$1</em>')
            // Convert [text](url) to <a href="url">text</a>
            .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>')
            // Convert double newlines to paragraph breaks
            .split(/\n\n+/)
            .map(p => `<div>${p.replace(/\n/g, '<br>')}</div>`)
            .join('')
    }
}
