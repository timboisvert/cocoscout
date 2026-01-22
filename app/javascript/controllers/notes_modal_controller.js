import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    connect() {
        this.modal = null
        this.backdrop = null
    }

    show(event) {
        event.preventDefault()
        event.stopPropagation()

        const notes = this.element.dataset.notesModalNotes

        if (!this.modal) {
            this.createModal(notes)
        }

        this.modal.classList.remove('hidden')
        this.backdrop.classList.remove('hidden')
    }

    close(event) {
        if (event) {
            event.preventDefault()
            event.stopPropagation()
        }

        if (this.modal) {
            this.modal.classList.add('hidden')
            this.backdrop.classList.add('hidden')
        }
    }

    createModal(notes) {
        // Create backdrop
        this.backdrop = document.createElement('div')
        this.backdrop.className = 'fixed inset-0 bg-black bg-opacity-50 hidden z-50'
        this.backdrop.addEventListener('click', () => this.close())
        document.body.appendChild(this.backdrop)

        // Create modal
        this.modal = document.createElement('div')
        this.modal.className = 'fixed top-1/2 left-1/2 transform -translate-x-1/2 -translate-y-1/2 bg-white rounded-lg shadow-xl max-w-md w-full mx-4 hidden z-50'

        this.modal.innerHTML = `
      <div class="flex items-center justify-between p-4 border-b border-gray-200">
        <h3 class="text-lg font-semibold text-gray-900">Notes</h3>
        <button type="button" class="text-gray-400 hover:text-gray-600">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6">
            <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>
      <div class="p-4 text-gray-700 whitespace-pre-wrap max-h-96 overflow-y-auto">
        ${notes}
      </div>
    `

        // Wire up close button
        this.modal.querySelector('button').addEventListener('click', () => this.close())

        document.body.appendChild(this.modal)
    }
}
