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
        const videoId = event.currentTarget.dataset.videoId
        const videoEl = document.querySelector(`[data-video-id="${videoId}"]`)

        if (!videoEl) return

        this.editingIdValue = videoId
        this.formTarget.querySelector('[data-field="title"]').value = videoEl.dataset.title || ''
        this.formTarget.querySelector('[data-field="url"]').value = videoEl.dataset.url || ''
        this.modalTarget.classList.remove("hidden")
    }

    save(event) {
        event.preventDefault()
        const formData = new FormData(this.formTarget)
        const title = formData.get('title')
        const url = formData.get('url')

        if (!title || !url) {
            alert('Please enter both title and URL')
            return
        }

        if (this.editingIdValue) {
            this.updateVideoInDOM(this.editingIdValue, title, url)
        } else {
            this.addVideoToDOM(title, url)
        }

        this.closeModal()
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
        }
    }

    addVideoToDOM(title, url) {
        const timestamp = new Date().getTime()

        const html = `
      <div class="border border-gray-200 rounded-lg p-4" data-video-id="new-${timestamp}" data-title="${this.escapeHtml(title)}" data-url="${this.escapeHtml(url)}">
        <input type="hidden" name="person[profile_videos_attributes][${timestamp}][title]" value="${this.escapeHtml(title)}">
        <input type="hidden" name="person[profile_videos_attributes][${timestamp}][url]" value="${this.escapeHtml(url)}">
        <input type="hidden" name="person[profile_videos_attributes][${timestamp}][position]" value="0">
        <input type="hidden" name="person[profile_videos_attributes][${timestamp}][_destroy]" value="0" class="destroy-field">

        <div class="flex items-center justify-between">
          <div class="flex-1">
            <div class="font-medium text-gray-900">${this.escapeHtml(title)}</div>
            <div class="text-sm text-gray-600 truncate">${this.escapeHtml(url)}</div>
          </div>
          <div class="flex gap-2 ml-4">
            <button type="button"
                    class="text-xs text-pink-500 hover:text-pink-700 underline"
                    data-action="click->profile-videos#edit"
                    data-video-id="new-${timestamp}">
              Edit
            </button>
            <button type="button"
                    class="text-xs text-pink-500 hover:text-pink-700"
                    data-action="click->profile-videos#remove"
                    data-video-id="new-${timestamp}">
              Remove
            </button>
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
