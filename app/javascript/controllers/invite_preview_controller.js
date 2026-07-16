import { Controller } from "@hotwired/stimulus"

// Opens a modal with the onboarding email draft (already interpolated) and lets
// the org edit the subject and (rich-text) body before (re)sending the invite.
export default class extends Controller {
    static targets = ["modal", "toName", "toEmail", "subject", "bodyInput", "bodyEditor", "form"]

    open(event) {
        if (event) event.preventDefault()
        const d = event.currentTarget.dataset

        if (this.hasFormTarget && d.invitePath) this.formTarget.action = d.invitePath
        this.toNameTargets.forEach(el => { el.textContent = d.toName || "" })
        if (this.hasToEmailTarget) this.toEmailTarget.textContent = d.toEmail || ""
        if (this.hasSubjectTarget) this.subjectTarget.value = d.emailSubject || ""

        const html = d.emailBody || ""
        if (this.hasBodyInputTarget) this.bodyInputTarget.value = html
        if (this.hasBodyEditorTarget && this.bodyEditorTarget.editor) {
            this.bodyEditorTarget.editor.loadHTML(html)
        }

        this.show()
    }

    close(event) {
        if (event) event.preventDefault()
        this.hide()
    }

    backdropClose(event) {
        if (event.target === this.modalTarget) this.hide()
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    show() { if (this.hasModalTarget) this.modalTarget.classList.remove("hidden") }
    hide() { if (this.hasModalTarget) this.modalTarget.classList.add("hidden") }
}
