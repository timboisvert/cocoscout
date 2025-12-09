import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["sectionModal", "creditModal", "sectionForm", "creditForm", "sectionsList", "creditsList", "yearEndInput", "ongoingCheckbox"]

    connect() {
        this.keyHandler = this.handleKeydown.bind(this)
    }

    disconnect() {
        document.removeEventListener('keydown', this.keyHandler)
    }

    // Toggle "Ongoing/Present" for year_end field
    toggleOngoing() {
        if (this.hasOngoingCheckboxTarget && this.hasYearEndInputTarget) {
            if (this.ongoingCheckboxTarget.checked) {
                this.yearEndInputTarget.value = ''
                this.yearEndInputTarget.disabled = true
                this.yearEndInputTarget.placeholder = 'Present'
            } else {
                this.yearEndInputTarget.disabled = false
                this.yearEndInputTarget.placeholder = 'To (optional)'
            }
        }
    }

    getEntityScope() {
        const form = this.element.querySelector('form') || document.getElementById('performance-history-form')
        if (!form) return 'person'

        const actionUrl = form.action
        if (actionUrl.includes('/groups/')) {
            return 'group'
        } else if (actionUrl.includes('/profile')) {
            return 'person'
        }

        return 'person'
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

            // Trigger auto-save
            const form = document.getElementById('performance-history-form')
            if (form) {
                form.requestSubmit()
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
        const fields = ['title', 'role', 'year_start', 'year_end', 'link_url', 'notes']
        fields.forEach(field => {
            const input = this.creditFormTarget.querySelector(`[data-field="${field}"]`)
            if (input) {
                input.value = ''
                input.disabled = false
            }
        })

        // Set default year to current year for year_start
        const yearStartField = this.creditFormTarget.querySelector('[data-field="year_start"]')
        if (yearStartField) {
            yearStartField.value = new Date().getFullYear()
        }

        // Reset ongoing checkbox
        if (this.hasOngoingCheckboxTarget) {
            this.ongoingCheckboxTarget.checked = false
        }
        if (this.hasYearEndInputTarget) {
            this.yearEndInputTarget.disabled = false
            this.yearEndInputTarget.placeholder = 'To (optional)'
        }

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

        // Handle ongoing checkbox
        const isOngoing = creditEl.dataset.ongoing === 'true'
        const yearEnd = creditEl.dataset.yearEnd || ''

        if (this.hasYearEndInputTarget) {
            this.yearEndInputTarget.value = isOngoing ? '' : yearEnd
            this.yearEndInputTarget.disabled = isOngoing
            this.yearEndInputTarget.placeholder = isOngoing ? 'Present' : 'To (optional)'
        }
        if (this.hasOngoingCheckboxTarget) {
            this.ongoingCheckboxTarget.checked = isOngoing
        }

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

        // Check if ongoing is selected
        const isOngoing = this.hasOngoingCheckboxTarget && this.ongoingCheckboxTarget.checked
        const yearEnd = isOngoing ? '' : (this.creditFormTarget.querySelector('[name="year_end"]')?.value?.trim() || '')

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
            title, role, year_start: yearStart, year_end: yearEnd, ongoing: isOngoing, link_url: linkUrl, notes
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

            // Trigger auto-save
            const form = document.getElementById('performance-history-form')
            if (form) {
                form.requestSubmit()
            }
        }
    }

    // Helper methods
    addSectionToDOM(name) {
        const timestamp = new Date().getTime()
        const container = this.sectionsListTarget
        const entityScope = this.getEntityScope()
        const position = container.querySelectorAll('[data-section-id]').length

        const html = `
      <div class="border border-gray-200 rounded-lg p-5 mb-4 bg-white shadow-sm group/section" data-section-id="new-${timestamp}" data-position="${position}">
        <input type="hidden" name="${entityScope}[performance_sections_attributes][${timestamp}][name]" value="${this.escapeHtml(name)}">
        <input type="hidden" name="${entityScope}[performance_sections_attributes][${timestamp}][position]" value="${position}">
        <input type="hidden" name="${entityScope}[performance_sections_attributes][${timestamp}][_destroy]" value="0" class="section-destroy-field">

        <div class="flex items-center justify-between mb-4 pb-3 border-b border-gray-200">
          <div class="flex items-center gap-3">
            <div class="section-drag-handle cursor-grab active:cursor-grabbing text-gray-400 hover:text-gray-600 opacity-0 group-hover/section:opacity-100 transition-opacity">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5" />
              </svg>
            </div>
            <h4 class="text-lg font-semibold text-gray-900 coustard-regular">${this.escapeHtml(name)}</h4>
          </div>
          <div class="flex gap-2 opacity-0 group-hover/section:opacity-100 transition-opacity">
            <button type="button"
                    class="inline-flex items-center justify-center gap-2 font-medium rounded transition-colors cursor-pointer whitespace-nowrap text-gray-700 hover:bg-gray-100 px-3 py-1.5 text-sm"
                    data-action="click->performance-credits#editSection"
                    data-section-id="new-${timestamp}"
                    data-section-name="${this.escapeHtml(name)}">
              <span>Edit Section</span>
            </button>
            <button type="button"
                    class="inline-flex items-center justify-center gap-2 font-medium rounded transition-colors cursor-pointer whitespace-nowrap text-gray-700 hover:bg-gray-100 px-3 py-1.5 text-sm"
                    data-action="click->performance-credits#removeSection"
                    data-section-id="new-${timestamp}">
              <span>Remove Section</span>
            </button>
          </div>
        </div>

        <div class="credits-list mb-4" data-section-id="new-${timestamp}" data-controller="reorderable" data-reorderable-handle-value=".credit-drag-handle">
          <div class="space-y-2" data-reorderable-target="list">
            <!-- Credits will be added here -->
          </div>
        </div>

        <button type="button"
                class="inline-flex items-center justify-center gap-2 font-medium rounded transition-colors cursor-pointer whitespace-nowrap bg-white hover:bg-pink-50 text-pink-600 border border-pink-200 hover:border-pink-300 px-3 py-1.5 text-sm"
                data-action="click->performance-credits#openCreditModal"
                data-section-id="new-${timestamp}">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4"><path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" /></svg>
          <span>Add Credit</span>
        </button>
      </div>
    `

        container.insertAdjacentHTML('beforeend', html)

        // Trigger auto-save
        const form = document.getElementById('performance-history-form')
        if (form) {
            form.requestSubmit()
        }
    }

    updateSectionInDOM(sectionId, name) {
        const sectionEl = document.querySelector(`[data-section-id="${sectionId}"]`)
        if (sectionEl) {
            sectionEl.querySelector('h4').textContent = name
            const nameInput = sectionEl.querySelector('input[name*="[name]"]')
            if (nameInput) nameInput.value = name
        }

        // Trigger auto-save
        const form = document.getElementById('performance-history-form')
        if (form) {
            form.requestSubmit()
        }
    }

    addCreditToDOM(sectionId, formData) {
        const timestamp = new Date().getTime()
        const creditsList = document.querySelector(`.credits-list[data-section-id="${sectionId}"]`)
        const entityScope = this.getEntityScope()

        if (!creditsList) return

        const title = formData.title || ''
        const role = formData.role || ''
        const yearStart = formData.year_start || ''
        const yearEnd = formData.year_end || ''
        const ongoing = formData.ongoing || false
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

        const yearDisplay = ongoing ? `${yearStart}-Present` : (yearEnd ? `${yearStart}-${yearEnd}` : yearStart)
        const displayText = [title, role, yearDisplay].filter(v => v).join(' • ')

        // Get the list container for new credits (the inner div with data-reorderable-target)
        const listContainer = creditsList.querySelector('[data-reorderable-target="list"]') || creditsList
        const position = listContainer.querySelectorAll('[data-credit-id]').length

        const html = `
      <div class="flex items-center justify-between py-3 px-4 bg-gray-50 hover:bg-gray-100 rounded-lg transition-colors credit-item group"
           data-credit-id="new-${timestamp}"
           data-title="${this.escapeHtml(title)}"
           data-role="${this.escapeHtml(role)}"
           data-year-start="${yearStart}"
           data-year-end="${yearEnd}"
           data-ongoing="${ongoing}"
           data-link-url="${this.escapeHtml(linkUrl)}"
           data-notes="${this.escapeHtml(notes)}"
           data-position="${position}">
        <input type="hidden" name="${entityScope}[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][title]" value="${this.escapeHtml(title)}">
        <input type="hidden" name="${entityScope}[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][role]" value="${this.escapeHtml(role)}">
        <input type="hidden" name="${entityScope}[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][year_start]" value="${yearStart}">
        <input type="hidden" name="${entityScope}[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][year_end]" value="${yearEnd}">
        <input type="hidden" name="${entityScope}[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][ongoing]" value="${ongoing}">
        <input type="hidden" name="${entityScope}[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][link_url]" value="${this.escapeHtml(linkUrl)}">
        <input type="hidden" name="${entityScope}[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][notes]" value="${this.escapeHtml(notes)}">
        <input type="hidden" name="${entityScope}[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][position]" value="${position}">
        <input type="hidden" name="${entityScope}[performance_sections_attributes][${sectionIndex}][performance_credits_attributes][${timestamp}][_destroy]" value="0" class="credit-destroy-field">

        <div class="flex items-center gap-3 flex-1 min-w-0">
          <div class="credit-drag-handle cursor-grab active:cursor-grabbing text-gray-400 hover:text-gray-600 opacity-0 group-hover:opacity-100 transition-opacity">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
              <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5" />
            </svg>
          </div>
          <div class="text-sm font-medium text-gray-900">${displayText || 'Untitled'}</div>
        </div>

        <div class="flex gap-2 ml-4 opacity-0 group-hover:opacity-100 transition-opacity">
          <button type="button"
                  class="inline-flex items-center justify-center gap-2 font-medium rounded transition-colors cursor-pointer whitespace-nowrap text-gray-700 hover:bg-gray-100 px-3 py-1.5 text-sm"
                  data-action="click->performance-credits#editCredit"
                  data-credit-id="new-${timestamp}"
                  data-section-id="${sectionId}">
            <span>Edit Credit</span>
          </button>
          <button type="button"
                  class="inline-flex items-center justify-center gap-2 font-medium rounded transition-colors cursor-pointer whitespace-nowrap text-gray-700 hover:bg-gray-100 px-3 py-1.5 text-sm"
                  data-action="click->performance-credits#removeCredit"
                  data-credit-id="new-${timestamp}">
            <span>Remove Credit</span>
          </button>
        </div>
      </div>
    `

        listContainer.insertAdjacentHTML('beforeend', html)

        // Trigger auto-save
        const form = document.getElementById('performance-history-form')
        if (form) {
            form.requestSubmit()
        }
    }

    updateCreditInDOM(creditId, formData) {
        const creditEl = document.querySelector(`[data-credit-id="${creditId}"]`)
        if (!creditEl) return

        const title = formData.title || ''
        const role = formData.role || ''
        const yearStart = formData.year_start || ''
        const yearEnd = formData.year_end || ''
        const ongoing = formData.ongoing || false
        const linkUrl = formData.link_url || ''
        const notes = formData.notes || ''

        // Update data attributes
        creditEl.dataset.title = title
        creditEl.dataset.role = role
        creditEl.dataset.yearStart = yearStart
        creditEl.dataset.yearEnd = yearEnd
        creditEl.dataset.ongoing = ongoing
        creditEl.dataset.linkUrl = linkUrl
        creditEl.dataset.notes = notes

        // Update hidden inputs
        creditEl.querySelector('input[name*="[title]"]').value = title
        creditEl.querySelector('input[name*="[role]"]').value = role
        creditEl.querySelector('input[name*="[year_start]"]').value = yearStart
        creditEl.querySelector('input[name*="[year_end]"]').value = yearEnd
        creditEl.querySelector('input[name*="[ongoing]"]').value = ongoing
        creditEl.querySelector('input[name*="[link_url]"]').value = linkUrl
        creditEl.querySelector('input[name*="[notes]"]').value = notes

        // Update display
        const yearDisplay = ongoing ? `${yearStart}-Present` : (yearEnd ? `${yearStart}-${yearEnd}` : yearStart)
        const displayText = [title, role, yearDisplay].filter(v => v).join(' • ')

        creditEl.querySelector('.text-sm').textContent = displayText || 'Untitled'

        // Trigger auto-save
        const form = document.getElementById('performance-history-form')
        if (form) {
            form.requestSubmit()
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
