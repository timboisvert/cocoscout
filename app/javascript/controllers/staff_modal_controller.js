import { Controller } from "@hotwired/stimulus"

// Drives the tabbed "Edit staff member" modal on the staffing hub. Adding staff
// now goes through the full-page wizard; this modal only edits an existing
// member across three tabs: Details, Roles, and Onboarding.
//
// The edit trigger button carries the member's current values as data
// attributes; openForEdit reads them, fills the form, and points the update /
// resend / remove forms at the right URLs.
export default class extends Controller {
    static targets = [
        "modal", "form", "title", "tab", "panel", "saveFooter",
        "prefFirst", "personalEmail", "jobTitle", "hourlyRate", "startDate", "manager",
        "roleCheckbox",
        "onboardingStatus", "resendButton", "resendLabel", "removeForm"
    ]
    static values = { updateUrlTemplate: String }

    openForEdit(event) {
        if (event) event.preventDefault()
        const d = event.currentTarget.dataset

        if (this.hasTitleTarget) this.titleTarget.textContent = `Edit ${d.personName || "staff member"}`
        if (this.hasFormTarget && this.hasUpdateUrlTemplateValue) {
            this.formTarget.action = this.updateUrlTemplateValue.replace(":id", d.memberId)
        }

        this.setValue(this.prefFirstTarget, d.prefFirst)
        this.setValue(this.personalEmailTarget, d.personalEmail)
        this.setValue(this.jobTitleTarget, d.title)
        this.setValue(this.hourlyRateTarget, d.hourlyRate)
        this.setValue(this.startDateTarget, d.startDate)
        this.setValue(this.managerTarget, d.managerId)

        let roleIds = []
        try { roleIds = JSON.parse(d.roleIds || "[]") } catch (_) {}
        this.roleCheckboxTargets.forEach(cb => { cb.checked = roleIds.includes(parseInt(cb.value, 10)) })

        this.setupOnboarding(d)
        this.switchTabTo("details")
        this.show()
    }

    setupOnboarding(d) {
        const pending = d.pending === "true"
        const state = d.onboardingState || "added"
        let status
        if (state === "completed") {
            status = "Onboarded — they've set up how they get paid."
        } else if (pending || state === "invited") {
            status = "Invited — waiting on them to create their account and finish setting up how they get paid."
        } else {
            status = "Added to staff but not yet invited to finish onboarding."
        }
        if (this.hasOnboardingStatusTarget) this.onboardingStatusTarget.textContent = status
        if (this.hasResendLabelTarget) this.resendLabelTarget.textContent = state === "added" ? "Send onboarding invite" : "Resend onboarding invite"

        // Point the resend button at the shared email-preview modal by copying
        // the member's draft onto its dataset (invite-preview#open reads these).
        if (this.hasResendButtonTarget) {
            const b = this.resendButtonTarget.dataset
            b.invitePath = d.invitePath || ""
            b.toName = d.personName || ""
            b.toEmail = d.toEmail || ""
            b.emailSubject = d.emailSubject || ""
            b.emailBody = d.emailBody || ""
            b.sendLabel = d.sendLabel || "Send email"
        }
        if (this.hasRemoveFormTarget && d.destroyPath) this.removeFormTarget.action = d.destroyPath
    }

    switchTab(event) {
        if (event) event.preventDefault()
        this.switchTabTo(event.currentTarget.dataset.tab)
    }

    switchTabTo(key) {
        this.tabTargets.forEach(t => {
            const active = t.dataset.tab === key
            t.classList.toggle("border-pink-500", active)
            t.classList.toggle("text-pink-600", active)
            t.classList.toggle("border-transparent", !active)
            t.classList.toggle("text-gray-500", !active)
        })
        this.panelTargets.forEach(p => p.classList.toggle("hidden", p.dataset.panel !== key))
        if (this.hasSaveFooterTarget) this.saveFooterTarget.classList.toggle("hidden", key === "onboarding")
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

    setValue(el, value) {
        if (el) el.value = (value == null || value === "null") ? "" : value
    }
}
