import { Controller } from "@hotwired/stimulus"

// Opens a modal that previews the onboarding email exactly as it will be sent
// (already interpolated), then lets the org confirm the send. Replaces the
// cheap browser confirm dialog for (re)sending onboarding invites.
export default class extends Controller {
    static targets = ["modal", "toName", "toEmail", "subject", "body", "form"]

    open(event) {
        if (event) event.preventDefault()
        const d = event.currentTarget.dataset

        if (this.hasFormTarget && d.invitePath) this.formTarget.action = d.invitePath
        this.toNameTargets.forEach(el => { el.textContent = d.toName || "" })
        if (this.hasToEmailTarget) this.toEmailTarget.textContent = d.toEmail || ""
        if (this.hasSubjectTarget) this.subjectTarget.textContent = d.emailSubject || ""
        if (this.hasBodyTarget) this.bodyTarget.innerHTML = d.emailBody || ""

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
