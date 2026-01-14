import { Controller } from "@hotwired/stimulus"

// Ensures Trix editor content is synced to hidden input before form submission
// This handles cases where Turbo submits the form before Trix has synced
export default class extends Controller {
    static targets = ["form"]

    connect() {
        if (this.hasFormTarget) {
            // Use capture phase to run before Turbo's submit handler
            this.boundSyncTrixContent = this.syncTrixContent.bind(this)
            this.formTarget.addEventListener("submit", this.boundSyncTrixContent, true)
            
            // Also listen for turbo:submit-start
            this.formTarget.addEventListener("turbo:submit-start", this.boundSyncTrixContent)
        }
    }

    disconnect() {
        if (this.hasFormTarget && this.boundSyncTrixContent) {
            this.formTarget.removeEventListener("submit", this.boundSyncTrixContent, true)
            this.formTarget.removeEventListener("turbo:submit-start", this.boundSyncTrixContent)
        }
    }

    syncTrixContent(event) {
        // Find all Trix editors in this form
        const trixEditors = this.formTarget.querySelectorAll("trix-editor")
        
        trixEditors.forEach(editor => {
            // Get the associated input element via the input attribute
            const inputId = editor.getAttribute("input")
            if (inputId) {
                const input = document.getElementById(inputId)
                if (input && editor.editor) {
                    // Sync the value from the editor's internal state
                    // Use editor.value which is what Trix uses to serialize content
                    const editorValue = editor.value
                    if (editorValue && input.value !== editorValue) {
                        input.value = editorValue
                    }
                }
            }
        })
    }
}
