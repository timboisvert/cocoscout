import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "form", "list", "nameField", "fileField"]

    connect() {
        // Set up keyboard handler for ESC key
        this.keyHandler = this.handleKeydown.bind(this)
    }

    disconnect() {
        document.removeEventListener('keydown', this.keyHandler)
    }

    handleKeydown(event) {
        if (event.key === 'Escape' && this.hasModalTarget) {
            this.closeModal()
        }
    }

    openModal() {
        if (this.hasModalTarget) {
            this.modalTarget.classList.remove('hidden')
            this.clearForm()
            document.addEventListener('keydown', this.keyHandler)
        }
    }

    closeModal() {
        if (this.hasModalTarget) {
            this.modalTarget.classList.add('hidden')
            this.clearForm()
            document.removeEventListener('keydown', this.keyHandler)
        }
    }

    clearForm() {
        if (this.hasFormTarget) {
            this.formTarget.reset()
            this.formTarget.dataset.resumeId = ""
        }
    }

    selectFile(event) {
        const file = event.target.files[0]
        if (file) {
            // Show file name in the form
            const fileNameDisplay = this.fileFieldTarget.parentElement.querySelector('.file-name')
            if (fileNameDisplay) {
                fileNameDisplay.textContent = file.name
            }
        }
    }

    save(event) {
        event.preventDefault()

        const name = this.nameFieldTarget.value.trim()
        const file = this.fileFieldTarget.files[0]
        const resumeId = this.formTarget.dataset.resumeId

        if (!name) {
            alert('Please enter a resume name')
            return
        }

        if (resumeId) {
            this.updateResume(resumeId, name)
        } else {
            if (!file) {
                alert('Please select a file')
                return
            }
            this.createResume(name, file)
        }
    }

    createResume(name, file) {
        // Create a temporary ID for the new resume
        const tempId = `new_${Date.now()}`

        // Add to DOM immediately for instant feedback
        const reader = new FileReader()
        reader.onload = (e) => {
            this.addResumeToDOM(tempId, name, file.name, e.target.result)
        }
        reader.readAsDataURL(file)

        this.closeModal()
    }

    addResumeToDOM(id, name, fileName, dataUrl) {
        if (!this.hasListTarget) return

        const position = this.listTarget.querySelectorAll('.resume-item').length

        const resumeHTML = `
      <div class="resume-item border border-gray-200 rounded-lg p-4" data-resume-id="${this.escapeHtml(id)}">
        <div class="flex items-start justify-between gap-4">
          <div class="flex-1">
            <div class="flex items-center gap-2 mb-1">
              <h4 class="font-medium text-gray-900">${this.escapeHtml(name)}</h4>
            </div>
            <p class="text-sm text-gray-600">${this.escapeHtml(fileName)}</p>
          </div>
          <div class="flex items-center gap-3">
            <button type="button"
                    class="text-xs text-pink-500 hover:text-pink-600 underline cursor-pointer"
                    data-action="click->profile-resumes#setPrimary"
                    data-resume-id="${this.escapeHtml(id)}">
              Set as Primary
            </button>
            <button type="button"
                    class="text-xs text-pink-500 hover:text-pink-600 cursor-pointer"
                    data-action="click->profile-resumes#edit"
                    data-resume-id="${this.escapeHtml(id)}"
                    data-resume-name="${this.escapeHtml(name)}">
              Edit
            </button>
            <button type="button"
                    class="text-xs text-pink-500 hover:text-pink-600 cursor-pointer"
                    data-action="click->profile-resumes#remove"
                    data-resume-id="${this.escapeHtml(id)}">
              Remove
            </button>
          </div>
        </div>

        <!-- Hidden fields for form submission -->
        <input type="hidden" name="person[profile_resumes_attributes][${position}][id]" value="${this.escapeHtml(id)}">
        <input type="hidden" name="person[profile_resumes_attributes][${position}][name]" value="${this.escapeHtml(name)}">
        <input type="hidden" name="person[profile_resumes_attributes][${position}][position]" value="${position}">
        <input type="hidden" name="person[profile_resumes_attributes][${position}][is_primary]" value="false">
        <input type="file"
               name="person[profile_resumes_attributes][${position}][file]"
               class="hidden"
               data-resume-file="${this.escapeHtml(id)}">
      </div>
    `

        this.listTarget.insertAdjacentHTML('beforeend', resumeHTML)

        // Set the file data on the hidden input
        const fileInput = this.listTarget.querySelector(`[data-resume-file="${id}"]`)
        if (fileInput && dataUrl) {
            // Convert data URL back to file
            fetch(dataUrl)
                .then(res => res.blob())
                .then(blob => {
                    const file = new File([blob], fileName, { type: blob.type })
                    const dataTransfer = new DataTransfer()
                    dataTransfer.items.add(file)
                    fileInput.files = dataTransfer.files
                })
        }
    }

    edit(event) {
        const button = event.currentTarget
        const resumeId = button.dataset.resumeId
        const resumeName = button.dataset.resumeName

        this.nameFieldTarget.value = resumeName
        this.formTarget.dataset.resumeId = resumeId

        // Hide file field for editing (we only change the name)
        if (this.hasFileFieldTarget) {
            this.fileFieldTarget.closest('.mb-4').style.display = 'none'
        }

        this.openModal()
    }

    updateResume(resumeId, newName) {
        const resumeItem = this.listTarget.querySelector(`[data-resume-id="${resumeId}"]`)
        if (!resumeItem) return

        // Update the displayed name
        const nameElement = resumeItem.querySelector('h4')
        if (nameElement) {
            nameElement.textContent = newName
        }

        // Update the hidden field
        const nameInput = resumeItem.querySelector('input[name*="[name]"]')
        if (nameInput) {
            nameInput.value = newName
        }

        // Update the edit button data
        const editButton = resumeItem.querySelector('[data-action*="edit"]')
        if (editButton) {
            editButton.dataset.resumeName = newName
        }

        this.closeModal()
    }

    remove(event) {
        const button = event.currentTarget
        const resumeId = button.dataset.resumeId

        if (!confirm('Are you sure you want to remove this resume?')) {
            return
        }

        const resumeItem = this.listTarget.querySelector(`[data-resume-id="${resumeId}"]`)
        if (!resumeItem) return

        // If this is a new resume, just remove it from the DOM
        if (resumeId.startsWith('new_')) {
            resumeItem.remove()
            return
        }

        // For existing resumes, mark for deletion
        const destroyInput = resumeItem.querySelector('input[name*="[_destroy]"]')
        if (destroyInput) {
            destroyInput.value = '1'
        } else {
            // Add destroy field if it doesn't exist
            const idInput = resumeItem.querySelector('input[name*="[id]"]')
            if (idInput) {
                const fieldName = idInput.name.replace('[id]', '[_destroy]')
                resumeItem.insertAdjacentHTML('beforeend', `<input type="hidden" name="${fieldName}" value="1">`)
            }
        }

        resumeItem.remove()
    }

    escapeHtml(text) {
        const div = document.createElement('div')
        div.textContent = text
        return div.innerHTML
    }
}
