import { Controller } from "@hotwired/stimulus"

// Modal for uploading a show's poster (or the entire production's poster).
// Handles: open/close, click-to-pick, drag-and-drop, preview, submit gating.
export default class extends Controller {
    static targets = ["modal", "form", "fileInput", "preview", "placeholder", "dropzone", "submitButton"]

    open(event) {
        if (event) event.preventDefault()
        if (this.hasModalTarget) this.modalTarget.classList.remove("hidden")
    }

    close(event) {
        if (event) event.preventDefault()
        if (this.hasModalTarget) this.modalTarget.classList.add("hidden")
    }

    backdropClose(event) {
        if (event.target === this.modalTarget) this.close(event)
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    pickFile(event) {
        if (event) event.preventDefault()
        if (this.hasFileInputTarget) this.fileInputTarget.click()
    }

    fileChanged(event) {
        const file = event?.target?.files?.[0]
        this.applyFile(file)
    }

    dragOver(event) {
        event.preventDefault()
        if (this.hasDropzoneTarget) {
            this.dropzoneTarget.classList.add("border-pink-500", "bg-pink-50")
        }
    }

    dragLeave(event) {
        event.preventDefault()
        if (this.hasDropzoneTarget) {
            this.dropzoneTarget.classList.remove("border-pink-500", "bg-pink-50")
        }
    }

    drop(event) {
        event.preventDefault()
        if (this.hasDropzoneTarget) {
            this.dropzoneTarget.classList.remove("border-pink-500", "bg-pink-50")
        }
        const file = event.dataTransfer?.files?.[0]
        if (!file) return
        // Mirror the dropped file into the hidden input so the form picks it up
        if (this.hasFileInputTarget) {
            const dt = new DataTransfer()
            dt.items.add(file)
            this.fileInputTarget.files = dt.files
        }
        this.applyFile(file)
    }

    applyFile(file) {
        if (!file) return
        if (!file.type.startsWith("image/")) {
            alert("Please choose an image file.")
            return
        }
        // Show preview
        const reader = new FileReader()
        reader.onload = (e) => {
            if (this.hasPreviewTarget) {
                this.previewTarget.src = e.target.result
                this.previewTarget.classList.remove("hidden")
            }
            if (this.hasPlaceholderTarget) {
                this.placeholderTarget.classList.add("hidden")
            }
        }
        reader.readAsDataURL(file)
        // Enable submit
        if (this.hasSubmitButtonTarget) {
            this.submitButtonTarget.disabled = false
            this.submitButtonTarget.classList.remove("opacity-50", "cursor-not-allowed")
        }
    }
}
