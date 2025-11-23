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
        if (event.key === 'Enter') {
            if (this.hasSectionModalTarget && !this.sectionModalTarget.classList.contains('hidden')) {
                event.preventDefault()
                this.saveSection(event)
            } else if (this.hasCreditModalTarget && !this.creditModalTarget.classList.contains('hidden')) {
                event.preventDefault()
                this.saveCredit(event)
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

        // Manually clear the field since sectionFormTarget is now a div
        const nameField = this.sectionFormTarget.querySelector('[data-field="name"]')
        if (nameField) nameField.value = ''

        // Update modal title
        const modalTitle = this.sectionModalTarget.querySelector('h3')
        if (modalTitle) modalTitle.textContent = 'Add Section'

        this.sectionModalTarget.classList.remove("hidden")
        document.addEventListener('keydown', this.keyHandler)

        // Focus the name field
        if (nameField) {
            setTimeout(() => nameField.focus(), 100)
        }
    }

    closeSectionModal() {
        this.sectionModalTarget.classList.add("hidden")
        document.removeEventListener('keydown', this.keyHandler)
    }

    editSection(event) {
        event.preventDefault()
        const sectionId = event.currentTarget.dataset.sectionId
        const sectionName = event.currentTarget.dataset.sectionName

        this.editingSectionIdValue = sectionId

        // Update modal title
        const modalTitle = this.sectionModalTarget.querySelector('h3')
        if (modalTitle) modalTitle.textContent = 'Edit Section'

        const nameField = this.sectionFormTarget.querySelector('[data-field="name"]')
        nameField.value = sectionName

        this.sectionModalTarget.classList.remove("hidden")
        document.addEventListener('keydown', this.keyHandler)

        // Focus and select the name field
        if (nameField) {
            setTimeout(() => {
                nameField.focus()
                nameField.select()
            }, 100)
        }
    }

    saveSection(event) {
        event.preventDefault()
        const nameField = this.sectionFormTarget.querySelector('[name="name"]')
        const name = nameField?.value

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

        // Submit the performance history form
        const form = document.getElementById('performance-history-form')
        if (form) {
            form.requestSubmit()
        } else {
            console.error('Could not find performance-history-form')
        }
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

            // Submit the form to save the deletion
            const form = document.getElementById('performance-history-form')
            if (form) {
                console.log('Submitting form for section removal:', form)
                form.requestSubmit()
            } else {
                console.error('Could not find form to submit for section removal')
            }
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

        // Manually clear fields since creditFormTarget is now a div
        const fields = ['title', 'role']
        fields.forEach(field => {
            const input = this.creditFormTarget.querySelector(`[data-field="${field}"]`)
            if (input) input.value = ''
        })

        // Update modal title
        const modalTitle = this.creditModalTarget.querySelector('h3')
        if (modalTitle) modalTitle.textContent = 'Add Performance Credit'

        this.creditModalTarget.classList.remove("hidden")
        document.addEventListener('keydown', this.keyHandler)
    }

    closeCreditModal() {
        this.creditModalTarget.classList.add("hidden")
        document.removeEventListener('keydown', this.keyHandler)
    }

    editCredit(event) {
        event.preventDefault()
        const button = event.currentTarget

        this.editingCreditIdValue = button.dataset.creditId
        this.currentSectionValue = button.dataset.sectionId

        // Update modal title
        const modalTitle = this.creditModalTarget.querySelector('h3')
        if (modalTitle) modalTitle.textContent = 'Edit Performance Credit'

        // Populate form with existing values
        const creditEl = button.closest('.credit-item')
        this.creditFormTarget.querySelector('[data-field="title"]').value = creditEl.dataset.title || ''
        this.creditFormTarget.querySelector('[data-field="role"]').value = creditEl.dataset.role || ''
        this.creditFormTarget.querySelector('[data-field="year_start"]').value = creditEl.dataset.yearStart || ''
        this.creditFormTarget.querySelector('[data-field="year_end"]').value = creditEl.dataset.yearEnd || ''
        this.creditFormTarget.querySelector('[data-field="link_url"]').value = creditEl.dataset.linkUrl || ''
        this.creditFormTarget.querySelector('[data-field="notes"]').value = creditEl.dataset.notes || ''

        this.creditModalTarget.classList.remove("hidden")
        document.addEventListener('keydown', this.keyHandler)
    }

    saveCredit(event) {
        event.preventDefault()

        // Get values directly from form fields
        const title = this.creditFormTarget.querySelector('[name="title"]')?.value?.trim() || ''
        const role = this.creditFormTarget.querySelector('[name="role"]')?.value?.trim() || ''
        const yearStart = this.creditFormTarget.querySelector('[name="year_start"]')?.value?.trim() || ''
        const yearEnd = this.creditFormTarget.querySelector('[name="year_end"]')?.value?.trim() || ''
        const linkUrl = this.creditFormTarget.querySelector('[name="link_url"]')?.value?.trim() || ''
        const notes = this.creditFormTarget.querySelector('[name="notes"]')?.value?.trim() || ''

        if (!title) {
            alert('Please enter a title')
            return
        }

        if (!yearStart) {
            alert('Please enter a start year')
            return
        }

        const formData = {
            title, role, year_start: yearStart, year_end: yearEnd, link_url: linkUrl, notes
        }

        if (this.editingCreditIdValue) {
            // Update existing credit
            this.updateCreditInDOM(this.editingCreditIdValue, formData)
        } else {
            // Add new credit
            this.addCreditToDOM(this.currentSectionValue, formData)
        }

        this.closeCreditModal()

        // Submit the form to save changes
        const form = document.getElementById('performance-history-form')
        if (form) {
            form.requestSubmit()
        } else {
            console.error('Could not find performance-history-form')
        }
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

            // Submit the form to save the deletion
            const form = document.getElementById('performance-history-form')
            if (form) {
                console.log('Submitting form for credit removal:', form)
                form.requestSubmit()
            } else {
                console.error('Could not find form to submit for credit removal')
            }
        }
    }

    // Helper methods
    addSectionToDOM(name) {
        const timestamp = new Date().getTime()
        const container = this.sectionsListTarget

        console.log('Adding section to container:', container)
        console.log('Container parent:', container.parentElement)
        console.log('Container is inside form:', container.closest('form'))

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

        console.log('Section added, checking if fields are in form...')
        const form = document.getElementById('performance-history-form')
        const addedFields = form.querySelectorAll(`input[name*="[${timestamp}]"]`)
        console.log(`Found ${addedFields.length} fields in form for timestamp ${timestamp}`, addedFields)
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

        const title = formData.title || ''
        const role = formData.role || ''
        const yearStart = formData.year_start || ''
        const yearEnd = formData.year_end || ''
        const linkUrl = formData.link_url || ''
        const notes = formData.notes || ''

        // Determine the parent attribute path (section index)
        const sectionEl = document.querySelector(`[data-section-id="${sectionId}"]`)
        let sectionIndex = String(sectionId).replace('new-', '')

        // Try to find existing section index from inputs
        const sectionInputs = sectionEl.querySelectorAll('input[name*="performance_sections_attributes"]')
        if (sectionInputs.length > 0) {
            const match = sectionInputs[0].name.match(/\[performance_sections_attributes\]\[(\d+)\]/)
            if (match) sectionIndex = match[1]
        }

        const yearDisplay = yearEnd ? `${yearStart}-${yearEnd}` : yearStart
        const displayText = [title, role, yearDisplay].filter(v => v).join(' • ')

        const html = `
      <div class="flex items-center justify-between py-3 px-4 bg-gray-50 hover:bg-gray-100 rounded-lg transition-colors credit-item group"
           data-credit-id="new-${timestamp}"
           data-title="${this.escapeHtml(title)}"
           data-role="${this.escapeHtml(role)}"
           data-year-start="${yearStart}"
           data-year-end="${yearEnd}"
           data-link-url="${this.escapeHtml(linkUrl)}"
           data-notes="${this.escapeHtml(notes)}">
        <input type="hidden" name="person[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][title]" value="${this.escapeHtml(title)}">
        <input type="hidden" name="person[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][role]" value="${this.escapeHtml(role)}">
        <input type="hidden" name="person[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][year_start]" value="${yearStart}">
        <input type="hidden" name="person[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][year_end]" value="${yearEnd}">
        <input type="hidden" name="person[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][link_url]" value="${this.escapeHtml(linkUrl)}">
        <input type="hidden" name="person[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][notes]" value="${this.escapeHtml(notes)}">
        <input type="hidden" name="person[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][position]" value="0">
        <input type="hidden" name="person[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][_destroy]" value="0" class="credit-destroy-field">

        <div class="flex-1 min-w-0">
          <div class="text-sm font-medium text-gray-900">${displayText || 'Untitled'}</div>
        </div>

        <div class="flex gap-3 ml-4 opacity-0 group-hover:opacity-100 transition-opacity">
          <button type="button"
                  class="text-xs text-pink-500 hover:text-pink-700 underline cursor-pointer"
                  data-action="click->performance-credits#editCredit"
                  data-credit-id="new-${timestamp}"
                  data-section-id="${sectionId}">
            Edit
          </button>
          <button type="button"
                  class="text-xs text-pink-500 hover:text-pink-700 underline cursor-pointer"
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

        const title = formData.title || ''
        const role = formData.role || ''
        const yearStart = formData.year_start || ''
        const yearEnd = formData.year_end || ''
        const linkUrl = formData.link_url || ''
        const notes = formData.notes || ''

        // Update data attributes
        creditEl.dataset.title = title
        creditEl.dataset.role = role
        creditEl.dataset.yearStart = yearStart
        creditEl.dataset.yearEnd = yearEnd
        creditEl.dataset.linkUrl = linkUrl
        creditEl.dataset.notes = notes

        // Update hidden inputs
        creditEl.querySelector('input[name*="[title]"]').value = title
        creditEl.querySelector('input[name*="[role]"]').value = role
        creditEl.querySelector('input[name*="[year_start]"]').value = yearStart
        creditEl.querySelector('input[name*="[year_end]"]').value = yearEnd
        creditEl.querySelector('input[name*="[link_url]"]').value = linkUrl
        creditEl.querySelector('input[name*="[notes]"]').value = notes

        // Update display
        const yearDisplay = yearEnd ? `${yearStart}-${yearEnd}` : yearStart
        const displayText = [title, role, yearDisplay].filter(v => v).join(' • ')

        creditEl.querySelector('.text-sm').textContent = displayText || 'Untitled'
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
