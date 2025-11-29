import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "form", "list", "nameField", "fileField"]

    connect() {
        // Set up keyboard handler for ESC key
        this.keyHandler = this.handleKeydown.bind(this)
        // Track pending submissions
        this.pendingSubmissions = new Map()
    }

    disconnect() {
        document.removeEventListener('keydown', this.keyHandler)
    }

    getEntityScope() {
        const form = this.element.querySelector('form') || document.getElementById('resumes-form')
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
        if (event.key === 'Escape' && this.hasModalTarget) {
            this.closeModal()
        } else if (event.key === 'Enter' && event.target.tagName === 'INPUT') {
            event.preventDefault()
            this.save(event)
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    openModal(event) {
        if (event) event.preventDefault()

        if (this.hasModalTarget) {
            this.modalTarget.classList.remove('hidden')

            if (!this.hasFormTarget) {
                return
            }

            // Update modal title if not already set by edit()
            const modalTitle = this.modalTarget.querySelector('h3')
            if (modalTitle && !this.formTarget.dataset.resumeId) {
                modalTitle.textContent = 'Add Resume'
            }

            // Show file field for new resumes
            const fileField = this.modalTarget.querySelector('[data-profile-resumes-target="fileField"]')
            if (fileField && !this.formTarget.dataset.resumeId) {
                const fileContainer = fileField.parentElement.parentElement
                if (fileContainer) fileContainer.style.display = 'block'
            }

            document.addEventListener('keydown', this.keyHandler)

            // Focus name field
            if (this.hasNameFieldTarget) {
                setTimeout(() => this.nameFieldTarget.focus(), 100)
            }
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
            this.nameFieldTarget.value = ''
            this.fileFieldTarget.value = ''
            this.formTarget.dataset.resumeId = ""

            // Clear file name display
            const fileNameDisplay = this.modalTarget.querySelector('.file-name')
            if (fileNameDisplay) fileNameDisplay.innerHTML = ''

            // Show file container for next use
            const fileField = this.modalTarget.querySelector('[data-profile-resumes-target="fileField"]')
            if (fileField) {
                const fileContainer = fileField.parentElement.parentElement
                if (fileContainer) fileContainer.style.display = 'block'
            }
        }
    }

    selectFile(event) {
        const file = event.target.files[0]
        if (file) {
            // Show file name with icon
            const fileNameDisplay = this.modalTarget.querySelector('.file-name')
            if (fileNameDisplay) {
                fileNameDisplay.innerHTML = `
                    <span class="inline-flex items-center gap-2 text-gray-700">
                        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4 text-pink-500">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z" />
                        </svg>
                        <span class="font-medium">${file.name}</span>
                    </span>
                `
            }
        }
    }

    save(event) {
        event.preventDefault()

        if (!this.hasFormTarget) {
            return
        }

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
        // Get the count of existing resumes to determine the index
        const existingCount = this.listTarget.querySelectorAll('.resume-item').length
        const timestamp = new Date().getTime()
        const entityScope = this.getEntityScope()

        // Create a container for the new resume
        const resumeDiv = document.createElement('div')
        resumeDiv.className = 'resume-item flex items-start gap-4 border border-gray-200 rounded-lg p-4'
        resumeDiv.dataset.resumeId = `new_${timestamp}`

        // Create preview thumbnail
        const previewDiv = document.createElement('div')
        previewDiv.className = 'flex-shrink-0 w-24 aspect-[8.5/11] rounded border border-gray-200 bg-gray-50 overflow-hidden'

        // Create content div
        const contentDiv = document.createElement('div')
        contentDiv.className = 'flex-1'
        contentDiv.innerHTML = `
          <h4 class="font-medium text-gray-900 mb-1">${this.escapeHtml(name)}</h4>
          <p class="text-sm text-gray-600">${this.escapeHtml(file.name)}</p>
          <div class="flex items-center gap-3 mt-2">
            <button type="button"
                    class="text-xs text-pink-500 hover:text-pink-600 cursor-pointer"
                    data-action="click->profile-resumes#edit"
                    data-resume-id="new_${timestamp}"
                    data-resume-name="${this.escapeHtml(name)}">
              Edit
            </button>
            <button type="button"
                    class="text-xs text-pink-500 hover:text-pink-600 cursor-pointer"
                    data-action="click->profile-resumes#remove"
                    data-resume-id="new_${timestamp}">
              Remove
            </button>
          </div>
        `

        // Add hidden fields for Rails nested attributes
        const hiddenFields = `
          <input type="hidden" name="${entityScope}[profile_resumes_attributes][${timestamp}][name]" value="${this.escapeHtml(name)}">
          <input type="hidden" name="${entityScope}[profile_resumes_attributes][${timestamp}][position]" value="${existingCount}">
        `
        resumeDiv.innerHTML = hiddenFields
        resumeDiv.appendChild(previewDiv)
        resumeDiv.appendChild(contentDiv)

        // Create and attach the file input with the actual file
        const fileInput = document.createElement('input')
        fileInput.type = 'file'
        fileInput.name = `${entityScope}[profile_resumes_attributes][${timestamp}][file]`
        fileInput.style.display = 'none'
        const dataTransfer = new DataTransfer()
        dataTransfer.items.add(file)
        fileInput.files = dataTransfer.files
        resumeDiv.appendChild(fileInput)

        // Show preview
        const reader = new FileReader()
        reader.onload = (e) => {
            if (file.type === 'application/pdf') {
                previewDiv.innerHTML = `
                  <div class="w-full h-full flex flex-col items-center justify-center p-2">
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-8 h-8 text-red-500">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z" />
                    </svg>
                    <p class="text-xs text-center text-gray-600 mt-1">PDF</p>
                  </div>
                `
            } else {
                previewDiv.innerHTML = `<img src="${e.target.result}" class="w-full h-full object-cover">`
            }
        }
        reader.readAsDataURL(file)

        // Add to the list
        this.listTarget.appendChild(resumeDiv)

        // Close modal first
        this.closeModal()

        // Submit the form immediately using FormData to ensure file is uploaded
        const form = document.getElementById('resumes-form')
        if (form) {
            const formData = new FormData(form)

            // The file input is already in the form with DataTransfer, but we need to ensure it's included
            // Remove any existing file field for this timestamp to avoid duplicates
            const existingFileKey = `${entityScope}[profile_resumes_attributes][${timestamp}][file]`
            if (formData.has(existingFileKey)) {
                formData.delete(existingFileKey)
            }

            // Add the file to FormData with the correct name
            formData.append(existingFileKey, file)

            // Create abort controller for this submission
            const abortController = new AbortController()
            const resumeId = `new_${timestamp}`
            this.pendingSubmissions.set(resumeId, abortController)

            // Submit using fetch
            fetch(form.action, {
                method: form.method,
                body: formData,
                headers: {
                    'Accept': 'text/vnd.turbo-stream.html',
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
                },
                signal: abortController.signal
            })
                .then(response => response.text())
                .then(html => {
                    this.pendingSubmissions.delete(resumeId)
                    Turbo.renderStreamMessage(html)
                    // Note: The Turbo stream will replace the entire list, including our temporary resume
                    // with the real server-rendered version that has the actual database ID
                })
                .catch(error => {
                    this.pendingSubmissions.delete(resumeId)
                })
        }
    }

    addResumeToDOM(id, name, fileName, dataUrl) {
        if (!this.hasListTarget) return

        const position = this.listTarget.querySelectorAll('.resume-item').length
        const entityScope = this.getEntityScope()

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
        <input type="hidden" name="${entityScope}[profile_resumes_attributes][${position}][id]" value="${this.escapeHtml(id)}">
        <input type="hidden" name="${entityScope}[profile_resumes_attributes][${position}][name]" value="${this.escapeHtml(name)}">
        <input type="hidden" name="${entityScope}[profile_resumes_attributes][${position}][position]" value="${position}">
        <input type="hidden" name="${entityScope}[profile_resumes_attributes][${position}][is_primary]" value="false">
        <input type="file"
               name="${entityScope}[profile_resumes_attributes][${position}][file]"
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
        event.preventDefault()
        const button = event.currentTarget
        const resumeId = button.dataset.resumeId
        const resumeName = button.dataset.resumeName

        if (!this.hasFormTarget) {
            return
        }

        this.nameFieldTarget.value = resumeName
        this.formTarget.dataset.resumeId = resumeId

        // Update modal title
        const modalTitle = this.modalTarget.querySelector('h3')
        if (modalTitle) modalTitle.textContent = 'Edit Resume'

        // Hide file field for editing (we only change the name)
        const fileField = this.modalTarget.querySelector('[data-profile-resumes-target="fileField"]')
        if (fileField) {
            const fileContainer = fileField.parentElement.parentElement
            if (fileContainer) fileContainer.style.display = 'none'
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

        // Submit the form to save changes
        const form = document.getElementById('resumes-form')
        if (form) {
            form.requestSubmit()
        }
    }

    remove(event) {
        const button = event.currentTarget
        const resumeId = button.dataset.resumeId

        if (!confirm('Are you sure you want to remove this resume?')) {
            return
        }

        const resumeItem = this.listTarget.querySelector(`[data-resume-id="${resumeId}"]`)
        if (!resumeItem) return

        // If this is a new resume (not yet saved), cancel the submission and remove from DOM
        if (resumeId.startsWith('new_')) {
            // Cancel pending submission if exists
            const abortController = this.pendingSubmissions.get(resumeId)
            if (abortController) {
                abortController.abort()
                this.pendingSubmissions.delete(resumeId)
            }
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

        // Hide the item
        resumeItem.style.display = 'none'

        // Submit the form to save the deletion
        const form = document.getElementById('resumes-form')
        if (form) {
            form.requestSubmit()
        }
    }

    escapeHtml(text) {
        const div = document.createElement('div')
        div.textContent = text
        return div.innerHTML
    }
}
