import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["input", "filename", "dropzone"]

    fileSelected(event) {
        const file = event.target.files[0]
        if (file && this.hasFilenameTarget) {
            this.filenameTarget.textContent = file.name
            this.filenameTarget.classList.remove("hidden")
        }
    }

    // Allow clicking the dropzone to trigger file selection
    triggerFileSelect() {
        if (this.hasInputTarget) {
            this.inputTarget.click()
        }
    }
}
