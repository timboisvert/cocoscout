import { Controller } from "@hotwired/stimulus"
import { confirmDialog } from "controllers/lib/confirm_dialog"

// Opens/closes the House Role modal and switches it between "new" and "edit"
// modes by reading data-* attributes from the clicked trigger. In edit mode a
// "Remove role" action deletes the role (delete lives in the modal, not on the
// row, so it works on touch).
export default class extends Controller {
    static targets = [
        "modal", "form", "title", "submitButton", "methodInput",
        "nameInput", "roleTypeSelect", "locationSelect", "requiredCount",
        "hourlyRate", "deleteButton",
        "payType", "flatRate", "hourlyRateWrap", "flatRateWrap"
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
        if (this.hasTitleTarget) this.titleTarget.textContent = "Add role"
        this.setSubmitText("Add role")
        this.editUrl = null
        if (this.hasDeleteButtonTarget) this.deleteButtonTarget.classList.add("hidden")
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
        if (this.hasHourlyRateTarget)    this.hourlyRateTarget.value    = btn.dataset.roleHourlyRate || ""
        if (this.hasPayTypeTarget)       this.payTypeTarget.value       = btn.dataset.rolePayType || "hourly"
        if (this.hasFlatRateTarget)      this.flatRateTarget.value      = btn.dataset.roleFlatRate || ""
        this.syncPayType()

        if (this.hasFormTarget && this.hasUpdateUrlTemplateValue) {
            // update (PATCH) and destroy (DELETE) share the same path
            this.editUrl = this.updateUrlTemplateValue.replace(":id", id)
            this.formTarget.action = this.editUrl
        }
        if (this.hasMethodInputTarget) this.methodInputTarget.value = "patch"
        if (this.hasTitleTarget) this.titleTarget.textContent = "Edit role"
        this.setSubmitText("Save changes")
        if (this.hasDeleteButtonTarget) this.deleteButtonTarget.classList.remove("hidden")
        this.show()
    }

    async destroyRole(event) {
        if (event) event.preventDefault()
        if (!this.editUrl) return
        if (!(await confirmDialog({
            title: "Remove role?",
            message: "Existing shifts using it will be kept.",
            confirmText: "Remove"
        }))) return

        const form = document.createElement("form")
        form.method = "post"
        form.action = this.editUrl
        const token = document.querySelector('meta[name="csrf-token"]')?.content
        form.innerHTML =
            `<input type="hidden" name="_method" value="delete">` +
            `<input type="hidden" name="authenticity_token" value="${token || ""}">`
        document.body.appendChild(form)
        form.submit()
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
        if (this.hasHourlyRateTarget)    this.hourlyRateTarget.value = ""
        if (this.hasPayTypeTarget)       this.payTypeTarget.value = "hourly"
        if (this.hasFlatRateTarget)      this.flatRateTarget.value = ""
        this.syncPayType()
    }

    setSubmitText(text) {
        if (!this.hasSubmitButtonTarget) return
        const span = this.submitButtonTarget.querySelector("span")
        if (span) span.textContent = text
    }

    // Only the field that prices this role is shown — an hourly rate sitting
    // next to a flat rate is an invitation to fill in the wrong one.
    payTypeChanged() {
        this.syncPayType()
    }

    syncPayType() {
        if (!this.hasPayTypeTarget) return
        const flat = this.payTypeTarget.value === "flat"
        if (this.hasHourlyRateWrapTarget) this.hourlyRateWrapTarget.classList.toggle("hidden", flat)
        if (this.hasFlatRateWrapTarget) this.flatRateWrapTarget.classList.toggle("hidden", !flat)
    }
}
