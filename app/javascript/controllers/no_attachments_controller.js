import { Controller } from "@hotwired/stimulus"

// Blocks file/image drops and pastes in a Trix editor.
//
// An attachment renders as <action-text-attachment>, and the contract PDF walks
// the document's HTML with a fixed tag whitelist — an embedded image would
// silently vanish from the signed PDF rather than fail loudly. Better to refuse
// it at the point someone tries.
export default class extends Controller {
    connect() {
        this.reject = this.reject.bind(this)
        this.element.addEventListener("trix-file-accept", this.reject)
    }

    disconnect() {
        this.element.removeEventListener("trix-file-accept", this.reject)
    }

    reject(event) {
        event.preventDefault()
        const editor = this.element.querySelector("trix-editor")
        if (editor) editor.setAttribute("data-attachment-blocked", "true")
    }
}
