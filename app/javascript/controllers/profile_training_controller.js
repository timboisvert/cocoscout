import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "form", "list"]

    connect() {
        this.keyHandler = this.handleKeydown.bind(this)
    }

    disconnect() {
        document.removeEventListener('keydown', this.keyHandler)
    }

    handleKeydown(event) {
        if (event.key === 'Escape' && this.hasModalTarget && !this.modalTarget.classList.contains('hidden')) {
            this.closeModal()
        }
        if (event.key === 'Enter' && this.hasModalTarget && !this.modalTarget.classList.contains('hidden')) {
            event.preventDefault()
            this.save(event)
        }
    }
    static values = {
        editingId: String
    }

    openModal(event) {
        event.preventDefault()
        this.editingIdValue = ''

        // Manually clear fields since formTarget is now a div
        this.formTarget.querySelector('[data-field="institution"]').value = ''
        this.formTarget.querySelector('[data-field="program"]').value = ''
        this.formTarget.querySelector('[data-field="year_start"]').value = ''
        this.formTarget.querySelector('[data-field="year_end"]').value = ''
        this.formTarget.querySelector('[data-field="notes"]').value = ''

        // Update modal title
        const modalTitle = this.modalTarget.querySelector('h3')
        if (modalTitle) modalTitle.textContent = 'Add Training/Education'

        this.modalTarget.classList.remove("hidden")
        document.addEventListener('keydown', this.keyHandler)

        // Focus the first field
        const firstField = this.formTarget.querySelector('[data-field="institution"]')
        if (firstField) {
            setTimeout(() => firstField.focus(), 100)
        }
    }

    closeModal() {
        this.modalTarget.classList.add("hidden")
        this.editingIdValue = ''

        // Manually clear fields since formTarget is now a div
        this.formTarget.querySelector('[data-field="institution"]').value = ''
        this.formTarget.querySelector('[data-field="program"]').value = ''
        this.formTarget.querySelector('[data-field="year_start"]').value = ''
        this.formTarget.querySelector('[data-field="year_end"]').value = ''
        this.formTarget.querySelector('[data-field="notes"]').value = ''

        document.removeEventListener('keydown', this.keyHandler)
    }

    edit(event) {
        event.preventDefault()
        const trainingId = event.currentTarget.dataset.trainingId
        const trainingEl = document.querySelector(`[data-training-id="${trainingId}"]`)

        if (!trainingEl) return

        this.editingIdValue = trainingId

        // Update modal title
        const modalTitle = this.modalTarget.querySelector('h3')
        if (modalTitle) modalTitle.textContent = 'Edit Training/Education'

        this.formTarget.querySelector('[data-field="institution"]').value = trainingEl.dataset.institution || ''
        this.formTarget.querySelector('[data-field="program"]').value = trainingEl.dataset.program || ''
        this.formTarget.querySelector('[data-field="year_start"]').value = trainingEl.dataset.yearStart || ''
        this.formTarget.querySelector('[data-field="year_end"]').value = trainingEl.dataset.yearEnd || ''
        this.formTarget.querySelector('[data-field="notes"]').value = trainingEl.dataset.notes || ''
        this.modalTarget.classList.remove("hidden")
    }

    save(event) {
        event.preventDefault()

        const institutionField = this.formTarget.querySelector('[data-field="institution"]')
        const programField = this.formTarget.querySelector('[data-field="program"]')
        const yearStartField = this.formTarget.querySelector('[data-field="year_start"]')
        const yearEndField = this.formTarget.querySelector('[data-field="year_end"]')
        const notesField = this.formTarget.querySelector('[data-field="notes"]')

        if (!institutionField || !programField || !yearStartField || !yearEndField || !notesField) {
            console.error('Missing form fields:', {
                institution: !!institutionField,
                program: !!programField,
                yearStart: !!yearStartField,
                yearEnd: !!yearEndField,
                notes: !!notesField
            })
            alert('Form fields not found. Please refresh the page.')
            return
        }

        const institution = institutionField.value
        const program = programField.value
        const yearStart = yearStartField.value
        const yearEnd = yearEndField.value
        const notes = notesField.value

        if (!institution || !program || !yearStart) {
            alert('Please enter institution, program, and start year')
            return
        }

        if (this.editingIdValue && this.editingIdValue !== '') {
            this.updateTrainingInDOM(this.editingIdValue, institution, program, yearStart, yearEnd, notes)
        } else {
            this.addTrainingToDOM(institution, program, yearStart, yearEnd, notes)
        }

        // Submit the main profile form to save changes
        // Use setTimeout to ensure DOM updates complete before submission
        setTimeout(() => {
            const form = document.getElementById('training-form')
            if (form) {
                form.requestSubmit()
                // Close modal after successful submission
                this.closeModal()
            }
        }, 50)
    }

    remove(event) {
        event.preventDefault()
        if (!confirm('Remove this training?')) return

        const trainingId = event.currentTarget.dataset.trainingId
        const trainingEl = document.querySelector(`[data-training-id="${trainingId}"]`)

        if (trainingEl) {
            const destroyInput = trainingEl.querySelector('.destroy-field')
            if (destroyInput) {
                destroyInput.value = '1'
            }
            trainingEl.style.display = 'none'

            // Submit the main profile form to save changes
            const form = document.getElementById('training-form')
            if (form) {
                console.log('Submitting form for training removal:', form)
                form.requestSubmit()
            } else {
                console.error('Could not find form to submit for training removal')
            }
        }
    }

    addTrainingToDOM(institution, program, yearStart, yearEnd, notes) {
        const timestamp = new Date().getTime()
        const displayParts = [program, institution, yearStart ? (yearEnd ? `${yearStart}-${yearEnd}` : yearStart) : null].filter(v => v)
        const displayText = displayParts.join(' • ')

        const html = `
      <div class="flex items-center justify-between py-3 px-4 bg-gray-50 hover:bg-gray-100 rounded-lg transition-colors group"
           data-training-id="new-${timestamp}"
           data-institution="${this.escapeHtml(institution)}"
           data-program="${this.escapeHtml(program)}"
           data-year-start="${yearStart}"
           data-year-end="${yearEnd}"
           data-notes="${this.escapeHtml(notes)}">
        <input type="hidden" name="person[training_credits_attributes][${timestamp}][institution]" value="${this.escapeHtml(institution)}">
        <input type="hidden" name="person[training_credits_attributes][${timestamp}][program]" value="${this.escapeHtml(program)}">
        <input type="hidden" name="person[training_credits_attributes][${timestamp}][year_start]" value="${yearStart}">
        <input type="hidden" name="person[training_credits_attributes][${timestamp}][year_end]" value="${yearEnd}">
        <input type="hidden" name="person[training_credits_attributes][${timestamp}][notes]" value="${this.escapeHtml(notes)}">
        <input type="hidden" name="person[training_credits_attributes][${timestamp}][position]" value="0">
        <input type="hidden" name="person[training_credits_attributes][${timestamp}][_destroy]" value="0" class="destroy-field">

        <div class="flex-1 min-w-0">
          <div class="text-sm font-medium text-gray-900">${displayText}</div>
        </div>

        <div class="flex gap-3 ml-4 opacity-0 group-hover:opacity-100 transition-opacity">
          <button type="button"
                  class="text-xs text-pink-500 hover:text-pink-700 underline cursor-pointer"
                  data-action="click->profile-training#edit"
                  data-training-id="new-${timestamp}">
            Edit
          </button>
          <button type="button"
                  class="text-xs text-pink-500 hover:text-pink-700 underline cursor-pointer"
                  data-action="click->profile-training#remove"
                  data-training-id="new-${timestamp}">
            Remove
          </button>
        </div>
      </div>
    `

        this.listTarget.insertAdjacentHTML('beforeend', html)
    }

    updateTrainingInDOM(trainingId, institution, program, yearStart, yearEnd, notes) {
        const trainingEl = document.querySelector(`[data-training-id="${trainingId}"]`)
        if (!trainingEl) return

        trainingEl.dataset.institution = institution
        trainingEl.dataset.program = program
        trainingEl.dataset.yearStart = yearStart
        trainingEl.dataset.yearEnd = yearEnd
        trainingEl.dataset.notes = notes

        trainingEl.querySelector('input[name*="[institution]"]').value = institution
        trainingEl.querySelector('input[name*="[program]"]').value = program
        trainingEl.querySelector('input[name*="[year_start]"]').value = yearStart
        trainingEl.querySelector('input[name*="[year_end]"]').value = yearEnd
        trainingEl.querySelector('input[name*="[notes]"]').value = notes

        const displayParts = [program, institution, yearStart ? (yearEnd ? `${yearStart}-${yearEnd}` : yearStart) : null].filter(v => v)
        const displayText = displayParts.join(' • ')

        const displayDiv = trainingEl.querySelector('.flex-1 .text-sm')
        displayDiv.textContent = displayText
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
