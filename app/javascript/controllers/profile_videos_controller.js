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
        this.editingIdValue = null

        // Manually clear fields since formTarget is now a div
        this.formTarget.querySelector('[data-field="title"]').value = ''
        this.formTarget.querySelector('[data-field="url"]').value = ''

        // Update modal title
        const modalTitle = this.modalTarget.querySelector('h3')
        if (modalTitle) modalTitle.textContent = 'Add Video'

        this.modalTarget.classList.remove("hidden")
        document.addEventListener('keydown', this.keyHandler)

        // Focus the first field (title)
        const firstField = this.formTarget.querySelector('[data-field="title"]')
        if (firstField) {
            setTimeout(() => firstField.focus(), 100)
        }
    }

    closeModal() {
        this.modalTarget.classList.add("hidden")
        this.editingIdValue = null

        // Manually clear fields since formTarget is now a div
        this.formTarget.querySelector('[data-field="title"]').value = ''
        this.formTarget.querySelector('[data-field="url"]').value = ''

        document.removeEventListener('keydown', this.keyHandler)
    }

    edit(event) {
        event.preventDefault()
        const videoId = event.currentTarget.dataset.videoId
        const videoEl = document.querySelector(`[data-video-id="${videoId}"]`)

        if (!videoEl) return

        this.editingIdValue = videoId

        // Update modal title
        const modalTitle = this.modalTarget.querySelector('h3')
        if (modalTitle) modalTitle.textContent = 'Edit Video'

        this.formTarget.querySelector('[data-field="title"]').value = videoEl.dataset.title || ''
        this.formTarget.querySelector('[data-field="url"]').value = videoEl.dataset.url || ''
        this.modalTarget.classList.remove("hidden")
    }

    save(event) {
        event.preventDefault()
        const title = this.formTarget.querySelector('[data-field="title"]').value
        const url = this.formTarget.querySelector('[data-field="url"]').value

        console.log('Save called with title:', title, 'url:', url)
        console.log('editingIdValue:', this.editingIdValue, 'type:', typeof this.editingIdValue)

        if (!title || !url) {
            alert('Please enter both title and URL')
            return
        }

        if (this.editingIdValue && this.editingIdValue !== 'null') {
            console.log('Editing existing video:', this.editingIdValue)
            this.updateVideoInDOM(this.editingIdValue, title, url)
        } else {
            console.log('Adding new video')
            this.addVideoToDOM(title, url)
        }

        this.closeModal()

        // Submit the form to save changes
        const form = document.getElementById('videos-form')
        console.log('Found form:', form)
        if (form) {
            console.log('Submitting form...')
            form.requestSubmit()
        } else {
            console.error('Could not find form to submit for video')
        }
    }

    remove(event) {
        event.preventDefault()
        if (!confirm('Remove this video?')) return

        const videoId = event.currentTarget.dataset.videoId
        const videoEl = document.querySelector(`[data-video-id="${videoId}"]`)

        if (videoEl) {
            const destroyInput = videoEl.querySelector('.destroy-field')
            if (destroyInput) {
                destroyInput.value = '1'
            }
            videoEl.style.display = 'none'

            // Submit the form to save the deletion
            const form = document.getElementById('videos-form')
            if (form) {
                form.requestSubmit()
            } else {
                console.error('Could not find form to submit for video removal')
            }
        }
    }

    addVideoToDOM(title, url) {
        const timestamp = new Date().getTime()

        const html = `
      <div class="border border-gray-200 rounded-lg overflow-hidden" data-video-id="new-${timestamp}" data-title="${this.escapeHtml(title)}" data-url="${this.escapeHtml(url)}">
        <input type="hidden" name="person[profile_videos_attributes][${timestamp}][title]" value="${this.escapeHtml(title)}">
        <input type="hidden" name="person[profile_videos_attributes][${timestamp}][url]" value="${this.escapeHtml(url)}">
        <input type="hidden" name="person[profile_videos_attributes][${timestamp}][position]" value="0">
        <input type="hidden" name="person[profile_videos_attributes][${timestamp}][_destroy]" value="0" class="destroy-field">

        <div class="p-4">
          <div class="flex items-center justify-between">
            <div class="flex-1">
              <div class="font-medium text-gray-900">${this.escapeHtml(title)}</div>
            </div>
            <div class="flex gap-2 ml-4">
              <button type="button"
                      class="text-sm text-pink-500 hover:text-pink-700 underline"
                      data-action="click->profile-videos#edit"
                      data-video-id="new-${timestamp}">
                Edit
              </button>
              <button type="button"
                      class="text-sm text-pink-500 hover:text-pink-700 underline"
                      data-action="click->profile-videos#remove"
                      data-video-id="new-${timestamp}">
                Remove
              </button>
            </div>
          </div>
        </div>
      </div>
    `

        this.listTarget.insertAdjacentHTML('beforeend', html)
    }

    updateVideoInDOM(videoId, title, url) {
        const videoEl = document.querySelector(`[data-video-id="${videoId}"]`)
        if (!videoEl) return

        videoEl.dataset.title = title
        videoEl.dataset.url = url

        videoEl.querySelector('input[name*="[title]"]').value = title
        videoEl.querySelector('input[name*="[url]"]').value = url

        videoEl.querySelector('.font-medium').textContent = title
        videoEl.querySelector('.text-sm').textContent = url
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
