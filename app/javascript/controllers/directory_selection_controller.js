import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["checkbox", "item", "link", "selectButton", "selectedCount", "count", "bulkActions", "dropdown", "selectAllButton"]

    connect() {
        this.selectedItems = new Map()
        this.selectionMode = false
        this.updateUI()
    }

    checkboxTargetConnected(checkbox) {
        // When new checkboxes are added (e.g., via infinite scroll),
        // show them if we're in selection mode
        if (this.selectionMode) {
            checkbox.classList.remove('hidden')
        }
    }

    linkTargetConnected(link) {
        // When new links are added, disable them if we're in selection mode
        if (this.selectionMode) {
            link.style.pointerEvents = 'none'
            link.classList.add('cursor-default')
        }
    }

    enableSelectionMode() {
        this.selectionMode = true

        // Show all checkboxes
        this.checkboxTargets.forEach(checkbox => {
            checkbox.classList.remove('hidden')
        })

        // Disable all links
        this.linkTargets.forEach(link => {
            link.style.pointerEvents = 'none'
            link.classList.add('cursor-default')
        })

        // Hide Select Multiple button
        this.selectButtonTarget.classList.add('hidden')

        // Show Select All button
        this.selectAllButtonTarget.classList.remove('hidden')

        this.updateUI()
    }

    disableSelectionMode() {
        this.selectionMode = false

        // Hide all checkboxes and uncheck them
        this.checkboxTargets.forEach(checkbox => {
            checkbox.classList.add('hidden')
            checkbox.checked = false
        })

        // Re-enable all links
        this.linkTargets.forEach(link => {
            link.style.pointerEvents = ''
            link.classList.remove('cursor-default')
        })

        // Show Select Multiple button
        this.selectButtonTarget.classList.remove('hidden')

        // Hide Select All button
        this.selectAllButtonTarget.classList.add('hidden')

        // Clear selection
        this.selectedItems.clear()

        this.updateUI()
    }

    selectAll() {
        // Check all visible checkboxes and add to selection
        this.itemTargets.forEach(item => {
            const checkbox = item.querySelector('[data-directory-selection-target="checkbox"]')
            const id = item.dataset.entryId
            const type = item.dataset.entryType
            const name = item.dataset.entryName
            const headshot = item.dataset.entryHeadshot || ''

            if (checkbox && !checkbox.checked) {
                checkbox.checked = true
                this.selectedItems.set(`${type}-${id}`, { id, type, name, headshot })
            }
        })

        this.updateUI()
    }

    toggleCheckbox(event) {
        const checkbox = event.target
        const item = checkbox.closest('[data-directory-selection-target="item"]')
        const id = item.dataset.entryId
        const type = item.dataset.entryType
        const name = item.dataset.entryName
        const headshot = item.dataset.entryHeadshot || ''

        if (checkbox.checked) {
            this.selectedItems.set(`${type}-${id}`, { id, type, name, headshot })
        } else {
            this.selectedItems.delete(`${type}-${id}`)
        }

        this.updateUI()
    }

    clickItem(event) {
        // Only handle clicks when in selection mode
        if (!this.selectionMode) return

        // Don't handle if clicking the checkbox itself
        if (event.target.type === 'checkbox') return

        // Find the item and its checkbox
        const item = event.currentTarget
        const checkbox = item.querySelector('[data-directory-selection-target="checkbox"]')

        if (checkbox) {
            // Toggle the checkbox
            checkbox.checked = !checkbox.checked

            // Trigger the change event to update selection
            const changeEvent = new Event('change', { bubbles: true })
            checkbox.dispatchEvent(changeEvent)
        }
    }

    preventNavigation(event) {
        if (this.selectionMode) {
            event.stopPropagation()
        }
    }

    updateUI() {
        const count = this.selectedItems.size

        if (this.selectionMode) {
            // Always show selection count and bulk actions in selection mode
            this.selectedCountTarget.classList.remove('hidden')
            this.countTarget.textContent = count
            this.bulkActionsTarget.classList.remove('hidden')
        } else {
            this.selectedCountTarget.classList.add('hidden')
            this.bulkActionsTarget.classList.add('hidden')
        }
    }

    toggleDropdown() {
        this.dropdownTarget.classList.toggle('hidden')
    }

    clearSelection() {
        this.disableSelectionMode()
        this.dropdownTarget.classList.add('hidden')
    }

    openContactModal() {
        if (this.selectedItems.size === 0) return

        // Hide dropdown
        this.dropdownTarget.classList.add('hidden')

        // Build recipient names and IDs for the compose modal
        const items = Array.from(this.selectedItems.values())
        const ids = items.map(item => item.id)

        // Find the compose message modal and update it
        const modal = document.getElementById('compose-message-modal')
        if (!modal) return

        // Update the modal title to show count
        const titleEl = modal.querySelector('[data-compose-message-target="title"]')
        if (titleEl) {
            titleEl.textContent = `Message ${items.length} ${items.length === 1 ? 'person' : 'people'}`
        }

        const singleRecipient = modal.querySelector('[data-compose-message-target="singleRecipient"]')
        const batchRecipients = modal.querySelector('[data-compose-message-target="batchRecipients"]')
        const nameTarget = modal.querySelector('[data-compose-message-target="recipientName"]')
        const headshotTarget = modal.querySelector('[data-compose-message-target="recipientHeadshot"]')

        // If only 1 recipient, show as single (no tooltip, name next to headshot)
        if (items.length === 1) {
            const item = items[0]
            if (singleRecipient) singleRecipient.classList.remove('hidden')
            if (batchRecipients) batchRecipients.classList.add('hidden')

            if (nameTarget) nameTarget.textContent = item.name
            if (headshotTarget) {
                if (item.headshot) {
                    headshotTarget.innerHTML = `<img src="${item.headshot}" alt="${item.name}" class="w-8 h-8 rounded-lg object-cover ring-2 ring-white">`
                } else {
                    const initials = item.name ? item.name.split(' ').map(n => n[0]).join('').toUpperCase().substring(0, 2) : '?'
                    headshotTarget.innerHTML = initials
                    headshotTarget.className = 'w-8 h-8 rounded-lg bg-pink-100 flex items-center justify-center text-pink-600 font-bold text-xs ring-2 ring-white'
                }
            }
        } else {
            // Multiple recipients - show stacked headshots with tooltips
            if (singleRecipient) singleRecipient.classList.add('hidden')
            if (batchRecipients) {
                batchRecipients.classList.remove('hidden')
                batchRecipients.innerHTML = this.renderStackedHeadshots(items)
            }
        }

        // Set hidden fields for batch mode
        const form = modal.querySelector('form')
        if (form) {
            // Set form action to the messages endpoint
            form.action = '/manage/messages'

            // Set recipient type to batch
            let recipientTypeField = form.querySelector('input[name="recipient_type"]')
            if (recipientTypeField) {
                recipientTypeField.value = 'batch'
            }

            // Clear any existing person_ids fields
            form.querySelectorAll('input[name="person_ids[]"]').forEach(el => el.remove())

            // Add person_ids hidden fields
            ids.forEach(id => {
                const input = document.createElement('input')
                input.type = 'hidden'
                input.name = 'person_ids[]'
                input.value = id
                form.appendChild(input)
            })
        }

        // Show the modal
        modal.classList.remove('hidden')
        document.body.style.overflow = 'hidden'

        // Focus the subject field
        const subjectField = modal.querySelector('input[name="subject"]')
        if (subjectField) {
            setTimeout(() => subjectField.focus(), 100)
        }
    }

    renderStackedHeadshots(items) {
        const maxVisible = 8
        const visibleItems = items.slice(0, maxVisible)
        const overflowCount = items.length - maxVisible

        let html = visibleItems.map(item => {
            const initials = item.name ? item.name.split(' ').map(n => n[0]).join('').toUpperCase().substring(0, 2) : '?'
            const headshot = item.headshot

            if (headshot) {
                return `
                    <span data-controller="tooltip" data-tooltip-text-value="${item.name}" class="relative">
                        <img src="${headshot}" alt="${item.name}"
                             class="w-8 h-8 rounded-lg object-cover ring-2 ring-white relative z-10 hover:z-20 hover:scale-110 transition-transform cursor-default">
                    </span>`
            } else {
                return `
                    <span data-controller="tooltip" data-tooltip-text-value="${item.name}" class="relative">
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

    closeContactModal() {
        // Legacy method - modal is now controlled by compose-message controller
        const modal = document.getElementById('compose-message-modal')
        if (modal) {
            modal.classList.add('hidden')
            document.body.style.overflow = ''
        }
    }

    closeModalOnBackdrop(event) {
        // No longer needed - handled by compose-message controller
    }

    stopPropagation(event) {
        event.stopPropagation()
    }
}
