import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["checkbox", "item", "link", "selectButton", "selectedCount", "count", "bulkActions", "dropdown", "modal", "modalContent", "modalCount", "recipients", "selectedIdsContainer", "selectAllButton"]

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

            if (checkbox && !checkbox.checked) {
                checkbox.checked = true
                this.selectedItems.set(`${type}-${id}`, { id, type, name })
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

        if (checkbox.checked) {
            this.selectedItems.set(`${type}-${id}`, { id, type, name })
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

        // Update modal count
        this.modalCountTarget.textContent = `${this.selectedItems.size} selected`

        // Render recipients
        this.renderRecipients()

        // Render hidden form fields
        this.renderHiddenFields()

        // Show modal
        this.modalTarget.classList.remove('hidden')
        document.body.style.overflow = 'hidden'
    }

    closeContactModal() {
        this.modalTarget.classList.add('hidden')
        document.body.style.overflow = ''
    }

    closeModalOnBackdrop(event) {
        if (event.target === this.modalTarget) {
            this.closeContactModal()
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    renderRecipients() {
        const html = Array.from(this.selectedItems.values()).map(item => {
            if (!item || !item.name) {
                return ''
            }

            const initials = item.name.split(' ').map(n => n[0]).join('').toUpperCase()

            return `
        <div class="flex items-center gap-2 p-2 bg-gray-50 border border-gray-200 rounded-lg">
          <div class="w-8 h-8 rounded-lg bg-pink-100 flex items-center justify-center text-pink-600 font-bold text-xs flex-shrink-0">
            ${initials}
          </div>
          <span class="text-xs font-medium text-gray-700 truncate">${item.name}</span>
        </div>
      `
        }).join('')

        this.recipientsTarget.innerHTML = html
    }

    renderHiddenFields() {
        const html = Array.from(this.selectedItems.values()).map(item => {
            return `<input type="hidden" name="person_ids[]" value="${item.id}" data-type="${item.type}">`
        }).join('')

        this.selectedIdsContainerTarget.innerHTML = html
    }
}
