import { Controller } from "@hotwired/stimulus"

// Opens/closes the House Role modal and switches it between "new" and "edit"
// modes by reading data-* attributes from the clicked trigger.
export default class extends Controller {
    static targets = [
        "modal", "form", "title", "submitButton", "methodInput",
        "nameInput", "roleTypeSelect", "locationSelect", "requiredCount",
        "startOffset", "endOffset"
    ]
    static values = {
        createUrl: String,
        updateUrlTemplate: String
    }

    openForNew(event) {
        if (event) event.preventDefault()
        this.resetForm()
        if (this.hasFormTarget && this.hasCreateUrlValue) {
            this.formTarget.action = this.createUrlValue
        }
        if (this.hasMethodInputTarget) this.methodInputTarget.value = "post"
        if (this.hasTitleTarget) this.titleTarget.textContent = "Add house role"
        this.setSubmitText("Add role")
        this.show()
    }

    openForEdit(event) {
        if (event) event.preventDefault()
        const btn = event.currentTarget
        const id = btn.dataset.roleId

        if (this.hasNameInputTarget)   this.nameInputTarget.value   = btn.dataset.roleName || ""
        if (this.hasRoleTypeSelectTarget) this.roleTypeSelectTarget.value = btn.dataset.roleType || "house"
        if (this.hasLocationSelectTarget) this.locationSelectTarget.value = btn.dataset.roleLocationId || ""
        if (this.hasRequiredCountTarget) this.requiredCountTarget.value = btn.dataset.roleRequiredCount || ""
        if (this.hasStartOffsetTarget)   this.startOffsetTarget.value   = btn.dataset.roleStartOffset || ""
        if (this.hasEndOffsetTarget)     this.endOffsetTarget.value     = btn.dataset.roleEndOffset || ""

        if (this.hasFormTarget && this.hasUpdateUrlTemplateValue) {
            this.formTarget.action = this.updateUrlTemplateValue.replace(":id", id)
        }
        if (this.hasMethodInputTarget) this.methodInputTarget.value = "patch"
        if (this.hasTitleTarget) this.titleTarget.textContent = "Edit house role"
        this.setSubmitText("Save changes")
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

    // --- private ---

    show() {
        if (this.hasModalTarget) this.modalTarget.classList.remove("hidden")
    }

    hide() {
        if (this.hasModalTarget) this.modalTarget.classList.add("hidden")
    }

    resetForm() {
        if (this.hasNameInputTarget)     this.nameInputTarget.value = ""
        if (this.hasRoleTypeSelectTarget) this.roleTypeSelectTarget.value = "house"
        if (this.hasLocationSelectTarget) this.locationSelectTarget.value = ""
        if (this.hasRequiredCountTarget) this.requiredCountTarget.value = "1"
        if (this.hasStartOffsetTarget)   this.startOffsetTarget.value = "-60"
        if (this.hasEndOffsetTarget)     this.endOffsetTarget.value = "60"
    }

    setSubmitText(text) {
        if (!this.hasSubmitButtonTarget) return
        const span = this.submitButtonTarget.querySelector("span")
        if (span) span.textContent = text
    }
}
