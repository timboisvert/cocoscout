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
    }
    static values = {
        editingId: String
    }

    openModal(event) {
        event.preventDefault()
        this.editingIdValue = null
        this.formTarget.reset()
        this.modalTarget.classList.remove("hidden")
        document.addEventListener('keydown', this.keyHandler)
    }

    closeModal() {
        this.modalTarget.classList.add("hidden")
        this.editingIdValue = null
        this.formTarget.reset()
        document.removeEventListener('keydown', this.keyHandler)
    }

    edit(event) {
        event.preventDefault()
        const trainingId = event.currentTarget.dataset.trainingId
        const trainingEl = document.querySelector(`[data-training-id="${trainingId}"]`)

        if (!trainingEl) return

        this.editingIdValue = trainingId
        this.formTarget.querySelector('[data-field="institution"]').value = trainingEl.dataset.institution || ''
        this.formTarget.querySelector('[data-field="program"]').value = trainingEl.dataset.program || ''
        this.formTarget.querySelector('[data-field="location"]').value = trainingEl.dataset.location || ''
        this.formTarget.querySelector('[data-field="year_start"]').value = trainingEl.dataset.yearStart || ''
        this.formTarget.querySelector('[data-field="year_end"]').value = trainingEl.dataset.yearEnd || ''
        this.formTarget.querySelector('[data-field="notes"]').value = trainingEl.dataset.notes || ''
        this.modalTarget.classList.remove("hidden")
    }

    save(event) {
        event.preventDefault()
        const formData = new FormData(this.formTarget)
        const institution = formData.get('institution')
        const program = formData.get('program')
        const location = formData.get('location')
        const yearStart = formData.get('year_start')
        const yearEnd = formData.get('year_end')
        const notes = formData.get('notes')

        if (!institution) {
            alert('Please enter an institution')
            return
        }

        if (this.editingIdValue) {
            this.updateTrainingInDOM(this.editingIdValue, institution, program, location, yearStart, yearEnd, notes)
        } else {
            this.addTrainingToDOM(institution, program, location, yearStart, yearEnd, notes)
        }

        this.closeModal()
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
        }
    }

    addTrainingToDOM(institution, program, location, yearStart, yearEnd, notes) {
        const timestamp = new Date().getTime()
        const displayText = [program, institution].filter(v => v).join(' • ')
        const yearDisplay = yearEnd ? `${yearStart}-${yearEnd}` : yearStart

        const html = `
      <div class="border border-gray-200 rounded-lg p-4"
           data-training-id="new-${timestamp}"
           data-institution="${this.escapeHtml(institution)}"
           data-program="${this.escapeHtml(program)}"
           data-location="${this.escapeHtml(location)}"
           data-year-start="${yearStart}"
           data-year-end="${yearEnd}"
           data-notes="${this.escapeHtml(notes)}">
        <input type="hidden" name="person[training_credits_attributes][${timestamp}][institution]" value="${this.escapeHtml(institution)}">
        <input type="hidden" name="person[training_credits_attributes][${timestamp}][program]" value="${this.escapeHtml(program)}">
        <input type="hidden" name="person[training_credits_attributes][${timestamp}][location]" value="${this.escapeHtml(location)}">
        <input type="hidden" name="person[training_credits_attributes][${timestamp}][year_start]" value="${yearStart}">
        <input type="hidden" name="person[training_credits_attributes][${timestamp}][year_end]" value="${yearEnd}">
        <input type="hidden" name="person[training_credits_attributes][${timestamp}][notes]" value="${this.escapeHtml(notes)}">
        <input type="hidden" name="person[training_credits_attributes][${timestamp}][position]" value="0">
        <input type="hidden" name="person[training_credits_attributes][${timestamp}][_destroy]" value="0" class="destroy-field">

        <div class="flex items-center justify-between">
          <div class="flex-1">
            <div class="font-medium text-gray-900">${displayText || institution}</div>
            ${location ? `<div class="text-sm text-gray-600">${this.escapeHtml(location)}</div>` : ''}
            ${yearDisplay ? `<div class="text-xs text-gray-500">${yearDisplay}</div>` : ''}
          </div>
          <div class="flex gap-2 ml-4">
            <button type="button"
                    class="text-xs text-pink-500 hover:text-pink-700 underline"
                    data-action="click->profile-training#edit"
                    data-training-id="new-${timestamp}">
              Edit
            </button>
            <button type="button"
                    class="text-xs text-pink-500 hover:text-pink-700"
                    data-action="click->profile-training#remove"
                    data-training-id="new-${timestamp}">
              Remove
            </button>
          </div>
        </div>
      </div>
    `

        this.listTarget.insertAdjacentHTML('beforeend', html)
    }

    updateTrainingInDOM(trainingId, institution, program, location, yearStart, yearEnd, notes) {
        const trainingEl = document.querySelector(`[data-training-id="${trainingId}"]`)
        if (!trainingEl) return

        trainingEl.dataset.institution = institution
        trainingEl.dataset.program = program
        trainingEl.dataset.location = location
        trainingEl.dataset.yearStart = yearStart
        trainingEl.dataset.yearEnd = yearEnd
        trainingEl.dataset.notes = notes

        trainingEl.querySelector('input[name*="[institution]"]').value = institution
        trainingEl.querySelector('input[name*="[program]"]').value = program
        trainingEl.querySelector('input[name*="[location]"]').value = location
        trainingEl.querySelector('input[name*="[year_start]"]').value = yearStart
        trainingEl.querySelector('input[name*="[year_end]"]').value = yearEnd
        trainingEl.querySelector('input[name*="[notes]"]').value = notes

        const displayText = [program, institution].filter(v => v).join(' • ')
        const yearDisplay = yearEnd ? `${yearStart}-${yearEnd}` : yearStart

        const displayDiv = trainingEl.querySelector('.flex-1')
        displayDiv.querySelector('.font-medium').textContent = displayText || institution

        const locationEl = displayDiv.querySelector('.text-sm')
        if (location) {
            if (locationEl) {
                locationEl.textContent = location
            } else {
                displayDiv.querySelector('.font-medium').insertAdjacentHTML('afterend', `<div class="text-sm text-gray-600">${this.escapeHtml(location)}</div>`)
            }
        } else if (locationEl) {
            locationEl.remove()
        }

        const yearEl = displayDiv.querySelector('.text-xs')
        if (yearDisplay) {
            if (yearEl) {
                yearEl.textContent = yearDisplay
            } else {
                displayDiv.insertAdjacentHTML('beforeend', `<div class="text-xs text-gray-500">${yearDisplay}</div>`)
            }
        } else if (yearEl) {
            yearEl.remove()
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
