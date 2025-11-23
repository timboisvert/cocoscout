import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["sectionModal", "creditModal", "sectionForm", "creditForm", "sectionsList", "creditsList"]

    connect() {
        this.keyHandler = this.handleKeydown.bind(this)
    }

    disconnect() {
        document.removeEventListener('keydown', this.keyHandler)
    }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            if (this.hasSectionModalTarget && !this.sectionModalTarget.classList.contains('hidden')) {
                this.closeSectionModal()
            } else if (this.hasCreditModalTarget && !this.creditModalTarget.classList.contains('hidden')) {
                this.closeCreditModal()
            }
        }
    }
    static values = {
        currentSection: Number,
        editingSectionId: Number,
        editingCreditId: Number
    }

    // Section Modal Methods
    openSectionModal(event) {
        event.preventDefault()
        this.editingSectionIdValue = null
        this.sectionFormTarget.reset()
        this.sectionModalTarget.classList.remove("hidden")
    }

    closeSectionModal() {
        this.sectionModalTarget.classList.add("hidden")
    }

    editSection(event) {
        event.preventDefault()
        const sectionId = event.currentTarget.dataset.sectionId
        const sectionName = event.currentTarget.dataset.sectionName

        this.editingSectionIdValue = sectionId
        this.sectionFormTarget.querySelector('[data-field="name"]').value = sectionName
        this.sectionModalTarget.classList.remove("hidden")
    }

    saveSection(event) {
        event.preventDefault()
        const formData = new FormData(this.sectionFormTarget)
        const name = formData.get('name')

        if (!name || name.trim() === '') {
            alert('Please enter a section name')
            return
        }

        if (this.editingSectionIdValue) {
            // Update existing section
            this.updateSectionInDOM(this.editingSectionIdValue, name)
        } else {
            // Add new section
            this.addSectionToDOM(name)
        }

        this.closeSectionModal()
    }

    removeSection(event) {
        event.preventDefault()
        if (!confirm('Remove this section and all its credits?')) return

        const sectionId = event.currentTarget.dataset.sectionId
        const sectionEl = document.querySelector(`[data-section-id="${sectionId}"]`)

        if (sectionEl) {
            // Mark for destruction
            const destroyInput = sectionEl.querySelector('.section-destroy-field')
            if (destroyInput) {
                destroyInput.value = '1'
            }
            sectionEl.style.display = 'none'
        }
    }

    // Credit Modal Methods
    openCreditModal(event) {
        event.preventDefault()
        const sectionId = event.currentTarget.dataset.sectionId

        if (!sectionId) {
            alert('Please create a section first')
            return
        }

        this.currentSectionValue = sectionId
        this.editingCreditIdValue = null
        this.creditFormTarget.reset()
        this.creditModalTarget.classList.remove("hidden")
    }

    closeCreditModal() {
        this.creditModalTarget.classList.add("hidden")
    }

    editCredit(event) {
        event.preventDefault()
        const button = event.currentTarget

        this.editingCreditIdValue = button.dataset.creditId
        this.currentSectionValue = button.dataset.sectionId

        // Populate form with existing values
        const creditEl = button.closest('.credit-item')
        this.creditFormTarget.querySelector('[data-field="venue"]').value = creditEl.dataset.venue || ''
        this.creditFormTarget.querySelector('[data-field="role"]').value = creditEl.dataset.role || ''
        this.creditFormTarget.querySelector('[data-field="title"]').value = creditEl.dataset.title || ''
        this.creditFormTarget.querySelector('[data-field="year_start"]').value = creditEl.dataset.yearStart || ''
        this.creditFormTarget.querySelector('[data-field="year_end"]').value = creditEl.dataset.yearEnd || ''
        this.creditFormTarget.querySelector('[data-field="link_url"]').value = creditEl.dataset.linkUrl || ''
        this.creditFormTarget.querySelector('[data-field="notes"]').value = creditEl.dataset.notes || ''

        this.creditModalTarget.classList.remove("hidden")
    }

    saveCredit(event) {
        event.preventDefault()
        const formData = new FormData(this.creditFormTarget)

        const venue = formData.get('venue')
        const role = formData.get('role')
        const title = formData.get('title')

        if (!venue && !role && !title) {
            alert('Please enter at least venue, role, or title')
            return
        }

        if (this.editingCreditIdValue) {
            // Update existing credit
            this.updateCreditInDOM(this.editingCreditIdValue, formData)
        } else {
            // Add new credit
            this.addCreditToDOM(this.currentSectionValue, formData)
        }

        this.closeCreditModal()
    }

    removeCredit(event) {
        event.preventDefault()
        if (!confirm('Remove this credit?')) return

        const creditId = event.currentTarget.dataset.creditId
        const creditEl = document.querySelector(`[data-credit-id="${creditId}"]`)

        if (creditEl) {
            // Mark for destruction
            const destroyInput = creditEl.querySelector('.credit-destroy-field')
            if (destroyInput) {
                destroyInput.value = '1'
            }
            creditEl.style.display = 'none'
        }
    }

    // Helper methods
    addSectionToDOM(name) {
        const timestamp = new Date().getTime()
        const container = this.sectionsListTarget

        const html = `
      <div class="border border-gray-200 rounded-lg p-4 mb-4" data-section-id="new-${timestamp}">
        <input type="hidden" name="person[performance_sections_attributes][${timestamp}][name]" value="${this.escapeHtml(name)}">
        <input type="hidden" name="person[performance_sections_attributes][${timestamp}][position]" value="0">
        <input type="hidden" name="person[performance_sections_attributes][${timestamp}][_destroy]" value="0" class="section-destroy-field">

        <div class="flex items-center justify-between mb-4">
          <h4 class="text-lg font-semibold text-gray-900 coustard-regular">${this.escapeHtml(name)}</h4>
          <div class="flex gap-2">
            <button type="button"
                    class="text-xs text-pink-500 hover:text-pink-700 underline"
                    data-action="click->performance-credits#editSection"
                    data-section-id="new-${timestamp}"
                    data-section-name="${this.escapeHtml(name)}">
              Edit Section
            </button>
            <button type="button"
                    class="text-xs text-pink-500 hover:text-pink-700"
                    data-action="click->performance-credits#removeSection"
                    data-section-id="new-${timestamp}">
              Remove
            </button>
          </div>
        </div>

        <div class="space-y-2 credits-list" data-section-id="new-${timestamp}">
          <!-- Credits will be added here -->
        </div>

        <button type="button"
                class="mt-2 text-sm text-pink-500 hover:text-pink-700 underline font-medium"
                data-action="click->performance-credits#openCreditModal"
                data-section-id="new-${timestamp}">
          + Add Credit
        </button>
      </div>
    `

        container.insertAdjacentHTML('beforeend', html)
    }

    updateSectionInDOM(sectionId, name) {
        const sectionEl = document.querySelector(`[data-section-id="${sectionId}"]`)
        if (sectionEl) {
            sectionEl.querySelector('h4').textContent = name
            const nameInput = sectionEl.querySelector('input[name*="[name]"]')
            if (nameInput) nameInput.value = name
        }
    }

    addCreditToDOM(sectionId, formData) {
        const timestamp = new Date().getTime()
        const creditsList = document.querySelector(`.credits-list[data-section-id="${sectionId}"]`)

        if (!creditsList) return

        const venue = formData.get('venue') || ''
        const role = formData.get('role') || ''
        const title = formData.get('title') || ''
        const yearStart = formData.get('year_start') || ''
        const yearEnd = formData.get('year_end') || ''
        const linkUrl = formData.get('link_url') || ''
        const notes = formData.get('notes') || ''

        // Determine the parent attribute path (section index)
        const sectionEl = document.querySelector(`[data-section-id="${sectionId}"]`)
        let sectionIndex = sectionId.replace('new-', '')

        // Try to find existing section index from inputs
        const sectionInputs = sectionEl.querySelectorAll('input[name*="performance_sections_attributes"]')
        if (sectionInputs.length > 0) {
            const match = sectionInputs[0].name.match(/\[performance_sections_attributes\]\[(\d+)\]/)
            if (match) sectionIndex = match[1]
        }

        const displayText = [venue, role, title].filter(v => v).join(' • ')
        const yearDisplay = yearEnd ? `${yearStart}-${yearEnd}` : yearStart

        const html = `
      <div class="flex items-center justify-between py-2 px-3 bg-gray-50 rounded credit-item"
           data-credit-id="new-${timestamp}"
           data-venue="${this.escapeHtml(venue)}"
           data-role="${this.escapeHtml(role)}"
           data-title="${this.escapeHtml(title)}"
           data-year-start="${yearStart}"
           data-year-end="${yearEnd}"
           data-link-url="${this.escapeHtml(linkUrl)}"
           data-notes="${this.escapeHtml(notes)}">
        <input type="hidden" name="person[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][title]" value="${this.escapeHtml(title)}">
        <input type="hidden" name="person[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][role]" value="${this.escapeHtml(role)}">
        <input type="hidden" name="person[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][venue]" value="${this.escapeHtml(venue)}">
        <input type="hidden" name="person[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][year_start]" value="${yearStart}">
        <input type="hidden" name="person[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][year_end]" value="${yearEnd}">
        <input type="hidden" name="person[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][link_url]" value="${this.escapeHtml(linkUrl)}">
        <input type="hidden" name="person[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][notes]" value="${this.escapeHtml(notes)}">
        <input type="hidden" name="person[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][position]" value="0">
        <input type="hidden" name="person[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][_destroy]" value="0" class="credit-destroy-field">

        <div class="flex-1">
          <div class="text-sm font-medium text-gray-900">${displayText || 'Untitled'}</div>
          ${yearDisplay ? `<div class="text-xs text-gray-600">${yearDisplay}</div>` : ''}
        </div>

        <div class="flex gap-2">
          <button type="button"
                  class="text-xs text-pink-500 hover:text-pink-700 underline"
                  data-action="click->performance-credits#editCredit"
                  data-credit-id="new-${timestamp}"
                  data-section-id="${sectionId}">
            Edit
          </button>
          <button type="button"
                  class="text-xs text-pink-500 hover:text-pink-700"
                  data-action="click->performance-credits#removeCredit"
                  data-credit-id="new-${timestamp}">
            Remove
          </button>
        </div>
      </div>
    `

        creditsList.insertAdjacentHTML('beforeend', html)
    }

    updateCreditInDOM(creditId, formData) {
        const creditEl = document.querySelector(`[data-credit-id="${creditId}"]`)
        if (!creditEl) return

        const venue = formData.get('venue') || ''
        const role = formData.get('role') || ''
        const title = formData.get('title') || ''
        const yearStart = formData.get('year_start') || ''
        const yearEnd = formData.get('year_end') || ''
        const linkUrl = formData.get('link_url') || ''
        const notes = formData.get('notes') || ''

        // Update data attributes
        creditEl.dataset.venue = venue
        creditEl.dataset.role = role
        creditEl.dataset.title = title
        creditEl.dataset.yearStart = yearStart
        creditEl.dataset.yearEnd = yearEnd
        creditEl.dataset.linkUrl = linkUrl
        creditEl.dataset.notes = notes

        // Update hidden inputs
        creditEl.querySelector('input[name*="[title]"]').value = title
        creditEl.querySelector('input[name*="[role]"]').value = role
        creditEl.querySelector('input[name*="[venue]"]').value = venue
        creditEl.querySelector('input[name*="[year_start]"]').value = yearStart
        creditEl.querySelector('input[name*="[year_end]"]').value = yearEnd
        creditEl.querySelector('input[name*="[link_url]"]').value = linkUrl
        creditEl.querySelector('input[name*="[notes]"]').value = notes

        // Update display
        const displayText = [venue, role, title].filter(v => v).join(' • ')
        const yearDisplay = yearEnd ? `${yearStart}-${yearEnd}` : yearStart

        creditEl.querySelector('.text-sm').textContent = displayText || 'Untitled'
        const yearEl = creditEl.querySelector('.text-xs')
        if (yearEl) {
            yearEl.textContent = yearDisplay
        } else if (yearDisplay) {
            const displayDiv = creditEl.querySelector('.flex-1')
            displayDiv.insertAdjacentHTML('beforeend', `<div class="text-xs text-gray-600">${yearDisplay}</div>`)
        }
    }

    escapeHtml(text) {
        const map = {
            '&': '&amp;',
            '<': '&lt;',
            '>': '&gt;',
            '"': '&quot;',
            "'": '&#039;'
        }
        return String(text).replace(/[&<>"']/g, m => map[m])
    }

    stopPropagation(event) {
        event.stopPropagation()
    }
}
