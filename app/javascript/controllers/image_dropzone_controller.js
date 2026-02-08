import { Controller } from "@hotwired/stimulus"

/**
 * Image Dropzone Controller
 *
 * A drag-and-drop image upload zone that supports multiple images.
 * Displays previews and integrates with standard file inputs.
 * Can be toggled with a button for a cleaner UI.
 *
 * Usage (always visible):
 *   <div data-controller="image-dropzone">
 *     <input type="file" name="images[]" multiple accept="image/*"
 *            data-image-dropzone-target="input"
 *            data-action="change->image-dropzone#filesSelected"
 *            class="hidden">
 *
 *     <div data-image-dropzone-target="dropzone"
 *          data-action="dragover->image-dropzone#dragOver
 *                       dragleave->image-dropzone#dragLeave
 *                       drop->image-dropzone#drop
 *                       click->image-dropzone#openFilePicker"
 *          class="border-2 border-dashed border-gray-300 rounded-lg p-4 cursor-pointer hover:border-pink-400 transition-colors">
 *       <span data-image-dropzone-target="placeholder">Drop images here or click to upload</span>
 *       <div data-image-dropzone-target="previews" class="hidden grid grid-cols-4 gap-2"></div>
 *     </div>
 *   </div>
 *
 * Usage (with toggle button):
 *   <div data-controller="image-dropzone">
 *     <button type="button" data-image-dropzone-target="toggleButton"
 *             data-action="click->image-dropzone#toggle">Add image(s)</button>
 *
 *     <input type="file" ... class="hidden">
 *
 *     <div data-image-dropzone-target="dropzone" class="hidden ...">
 *       ...
 *     </div>
 *   </div>
 */
export default class extends Controller {
    static targets = ["input", "dropzone", "previews", "placeholder", "toggleButton"]
    static values = {
        maxFiles: { type: Number, default: 10 },
        maxSizeMb: { type: Number, default: 10 }
    }

    files = []

    connect() {
        // Prevent default drag behaviors on the whole document
        this.preventDefaults = (e) => {
            e.preventDefault()
            e.stopPropagation()
        }

        document.addEventListener('dragover', this.preventDefaults)
        document.addEventListener('drop', this.preventDefaults)

        // Find the parent form and intercept submission to append files
        // BUT only if the form isn't handled by compose-message or contact-production controllers
        this.form = this.element.closest('form')
        if (this.form) {
            const formParent = this.form.closest('[data-controller*="compose-message"], [data-controller*="contact-production"]')
            if (!formParent) {
                // Only add our submit handler if no other controller is handling this form
                this.submitHandler = this.handleFormSubmit.bind(this)
                // Use capture phase to run before other handlers
                this.form.addEventListener('submit', this.submitHandler, { capture: true })
            }
        }
    }

    disconnect() {
        document.removeEventListener('dragover', this.preventDefaults)
        document.removeEventListener('drop', this.preventDefaults)
        if (this.form && this.submitHandler) {
            this.form.removeEventListener('submit', this.submitHandler, { capture: true })
        }
    }

    // Intercept form submission to manually append files
    handleFormSubmit(event) {
        // Always sync files if we have any
        if (this.files.length > 0) {
            this.syncToInput()
        }

        // Check if sync worked (or no files needed)
        if (this.files.length === 0 || (this.hasInputTarget && this.inputTarget.files.length > 0)) {
            // Native form submission - set cookie for notice since flash can be unreliable
            document.cookie = 'flash_notice=Message sent successfully; path=/; max-age=10'
            console.log('[image-dropzone] Native form submit proceeding')
            return // Let native form submission proceed
        }

        // Sync didn't work - submit via XHR
        console.log('[image-dropzone] Sync failed, using XHR with', this.files.length, 'files')

        event.preventDefault()
        event.stopPropagation()
        event.stopImmediatePropagation()

        const formData = new FormData(this.form)
        formData.delete('images[]')
        this.files.forEach(file => formData.append('images[]', file))

        const xhr = new XMLHttpRequest()
        xhr.open(this.form.method || 'POST', this.form.action, true)

        xhr.onload = () => {
            if (xhr.status >= 200 && xhr.status < 400) {
                // Set a cookie that the server will read as a flash notice
                document.cookie = 'flash_notice=Message sent successfully; path=/; max-age=10'
                window.location.replace(xhr.responseURL)
            } else {
                console.error('[image-dropzone] XHR failed:', xhr.status)
                alert('Failed to send message. Please try again.')
            }
        }

        xhr.onerror = () => {
            console.error('[image-dropzone] XHR error')
            alert('Failed to send message. Please try again.')
        }

        xhr.send(formData)
        return false
    }

    toggle(event) {
        event?.preventDefault()
        if (this.hasDropzoneTarget) {
            const isHidden = this.dropzoneTarget.classList.contains('hidden')
            this.dropzoneTarget.classList.toggle('hidden')

            // Update button text if present
            if (this.hasToggleButtonTarget) {
                if (isHidden) {
                    this.toggleButtonTarget.classList.add('hidden')
                    this.element.classList.add('w-full')
                }
            }
        }
    }

    close(event) {
        event?.preventDefault()
        event?.stopPropagation()

        // Clear files
        this.files = []
        if (this.hasInputTarget) {
            this.inputTarget.value = ''
        }

        // Reset previews
        if (this.hasPreviewsTarget) {
            this.previewsTarget.innerHTML = ''
            this.previewsTarget.classList.add('hidden')
        }
        if (this.hasPlaceholderTarget) {
            this.placeholderTarget.classList.remove('hidden')
        }

        // Hide dropzone, show toggle button
        if (this.hasDropzoneTarget) {
            this.dropzoneTarget.classList.add('hidden')
        }
        if (this.hasToggleButtonTarget) {
            this.toggleButtonTarget.classList.remove('hidden')
        }
        this.element.classList.remove('w-full')
    }

    show() {
        if (this.hasDropzoneTarget) {
            this.dropzoneTarget.classList.remove('hidden')
        }
        if (this.hasToggleButtonTarget) {
            this.toggleButtonTarget.classList.add('hidden')
        }
        this.element.classList.add('w-full')
    }

    hide() {
        if (this.hasDropzoneTarget && this.files.length === 0) {
            this.dropzoneTarget.classList.add('hidden')
        }
        if (this.hasToggleButtonTarget && this.files.length === 0) {
            this.toggleButtonTarget.classList.remove('hidden')
        }
        if (this.files.length === 0) {
            this.element.classList.remove('w-full')
        }
    }

    dragOver(event) {
        event.preventDefault()
        event.stopPropagation()
        if (this.hasDropzoneTarget) {
            this.dropzoneTarget.classList.add('border-pink-400', 'bg-pink-50')
        }
    }

    dragLeave(event) {
        event.preventDefault()
        event.stopPropagation()
        if (this.hasDropzoneTarget) {
            this.dropzoneTarget.classList.remove('border-pink-400', 'bg-pink-50')
        }
    }

    drop(event) {
        event.preventDefault()
        event.stopPropagation()

        if (this.hasDropzoneTarget) {
            this.dropzoneTarget.classList.remove('border-pink-400', 'bg-pink-50')
        }

        const droppedFiles = event.dataTransfer?.files
        if (droppedFiles) {
            this.addFiles(droppedFiles)
        }
    }

    openFilePicker(event) {
        // Don't open if clicking a remove button
        if (event.target.closest('[data-action*="remove"]')) return

        if (this.hasInputTarget) {
            this.inputTarget.click()
        }
    }

    filesSelected(event) {
        const selectedFiles = event.target.files
        if (selectedFiles) {
            this.addFiles(selectedFiles)
        }
        // Reset input so the same file can be selected again
        event.target.value = ''
    }

    addFiles(fileList) {
        const newFiles = Array.from(fileList).filter(file => {
            // Only accept images
            if (!file.type.startsWith('image/')) {
                console.warn(`Skipping non-image file: ${file.name}`)
                return false
            }
            // Check file size
            if (file.size > this.maxSizeMbValue * 1024 * 1024) {
                console.warn(`File too large: ${file.name} (max ${this.maxSizeMbValue}MB)`)
                return false
            }
            // Check if already added (by name and size)
            const isDuplicate = this.files.some(f => f.name === file.name && f.size === file.size)
            if (isDuplicate) {
                console.warn(`Duplicate file: ${file.name}`)
                return false
            }
            return true
        })

        // Respect max files limit
        const remaining = this.maxFilesValue - this.files.length
        const filesToAdd = newFiles.slice(0, remaining)

        if (filesToAdd.length < newFiles.length) {
            console.warn(`Only adding ${filesToAdd.length} of ${newFiles.length} files (max ${this.maxFilesValue})`)
        }

        this.files.push(...filesToAdd)
        this.updatePreviews()
        this.syncToInput()
    }

    removeFile(event) {
        event.preventDefault()
        event.stopPropagation()

        const index = parseInt(event.currentTarget.dataset.index, 10)
        if (!isNaN(index) && index >= 0 && index < this.files.length) {
            this.files.splice(index, 1)
            this.updatePreviews()
            this.syncToInput()
        }
    }

    updatePreviews() {
        if (!this.hasPreviewsTarget) return

        if (this.files.length === 0) {
            this.previewsTarget.classList.add('hidden')
            this.previewsTarget.innerHTML = ''
            if (this.hasPlaceholderTarget) {
                this.placeholderTarget.classList.remove('hidden')
            }
            return
        }

        // Show previews, hide placeholder
        this.previewsTarget.classList.remove('hidden')
        if (this.hasPlaceholderTarget) {
            this.placeholderTarget.classList.add('hidden')
        }

        // Build preview HTML
        this.previewsTarget.innerHTML = this.files.map((file, index) => {
            const url = URL.createObjectURL(file)
            return `
                <div class="relative group">
                    <div class="w-20 h-20 rounded-lg overflow-hidden border border-gray-200 bg-gray-100">
                        <img src="${url}" alt="${file.name}"
                             class="w-full h-full object-cover">
                    </div>
                    <button type="button"
                            data-action="click->image-dropzone#removeFile"
                            data-index="${index}"
                            class="absolute -top-1.5 -right-1.5 w-5 h-5 bg-pink-500 hover:bg-pink-600 text-white rounded-full flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity shadow cursor-pointer">
                        <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                        </svg>
                    </button>
                </div>
            `
        }).join('')
    }

    syncToInput() {
        // Create a new DataTransfer to update the file input
        if (!this.hasInputTarget) {
            console.error('[image-dropzone] No input target found!')
            return
        }

        const dt = new DataTransfer()
        this.files.forEach(file => dt.items.add(file))
        this.inputTarget.files = dt.files
        console.log('[image-dropzone] syncToInput: set', this.files.length, 'files on input, input.files.length =', this.inputTarget.files.length)
    }

    // Public method to clear all files (e.g., after form submission)
    clear() {
        this.files = []
        this.updatePreviews()
        this.syncToInput()
    }

    // Get current file count
    get fileCount() {
        return this.files.length
    }
}
