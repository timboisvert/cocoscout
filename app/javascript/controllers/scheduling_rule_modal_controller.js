import { Controller } from "@hotwired/stimulus"
import { confirmDialog } from "controllers/lib/confirm_dialog"

// Opens/closes the Regulars rule modal and switches it between "new" and
// "edit" modes by reading data-* attributes from the clicked row. The rule
// type select swaps the production picker for the weekday/time fields. In
// edit mode a "Remove this regular" action deletes the rule (delete lives in
// the modal, not on the row, so it works on touch).
export default class extends Controller {
    static targets = [
        "modal", "form", "title", "submitButton", "methodInput",
        "personSelect", "houseRoleSelect", "ruleTypeSelect",
        "productionWrap", "productionSelect",
        "weekdayWrap", "daySelect", "startsTime", "endsTime",
        "deleteButton"
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
        if (this.hasTitleTarget) this.titleTarget.textContent = "Add a regular"
        this.setSubmitText("Add regular")
        this.editUrl = null
        if (this.hasDeleteButtonTarget) this.deleteButtonTarget.classList.add("hidden")
        this.show()
    }

    openForEdit(event) {
        if (event) event.preventDefault()
        const row = event.currentTarget
        const id = row.dataset.ruleId

        if (this.hasPersonSelectTarget)    this.personSelectTarget.value    = row.dataset.rulePersonId || ""
        if (this.hasHouseRoleSelectTarget) this.houseRoleSelectTarget.value = row.dataset.ruleHouseRoleId || ""
        if (this.hasRuleTypeSelectTarget)  this.ruleTypeSelectTarget.value  = row.dataset.ruleRuleType || "production_anchored"
        if (this.hasProductionSelectTarget) this.productionSelectTarget.value = row.dataset.ruleProductionId || ""
        if (this.hasDaySelectTarget)       this.daySelectTarget.value       = row.dataset.ruleDayOfWeek || ""
        if (this.hasStartsTimeTarget)      this.startsTimeTarget.value      = row.dataset.ruleStartsTime || ""
        if (this.hasEndsTimeTarget)        this.endsTimeTarget.value        = row.dataset.ruleEndsTime || ""
        this.syncRuleType()

        if (this.hasFormTarget && this.hasUpdateUrlTemplateValue) {
            // update (PATCH) and destroy (DELETE) share the same path
            this.editUrl = this.updateUrlTemplateValue.replace(":id", id)
            this.formTarget.action = this.editUrl
        }
        if (this.hasMethodInputTarget) this.methodInputTarget.value = "patch"
        if (this.hasTitleTarget) this.titleTarget.textContent = "Edit regular"
        this.setSubmitText("Save changes")
        if (this.hasDeleteButtonTarget) this.deleteButtonTarget.classList.remove("hidden")
        this.show()
    }

    async destroyRule(event) {
        if (event) event.preventDefault()
        if (!this.editUrl) return
        if (!(await confirmDialog({
            title: "Remove this regular?",
            message: "Shifts already created from it will be kept.",
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
        if (this.hasPersonSelectTarget)     this.personSelectTarget.value = ""
        if (this.hasHouseRoleSelectTarget)  this.houseRoleSelectTarget.value = ""
        if (this.hasRuleTypeSelectTarget)   this.ruleTypeSelectTarget.value = "production_anchored"
        if (this.hasProductionSelectTarget) this.productionSelectTarget.value = ""
        if (this.hasDaySelectTarget)        this.daySelectTarget.value = ""
        if (this.hasStartsTimeTarget)       this.startsTimeTarget.value = ""
        if (this.hasEndsTimeTarget)         this.endsTimeTarget.value = ""
        this.syncRuleType()
    }

    setSubmitText(text) {
        if (!this.hasSubmitButtonTarget) return
        const span = this.submitButtonTarget.querySelector("span")
        if (span) span.textContent = text
    }

    ruleTypeChanged() {
        this.syncRuleType()
    }

    // Only the fields for the chosen rule shape are shown — a production
    // picker next to weekday times invites filling in the wrong half. The
    // server clears whichever half doesn't apply, so a hidden leftover value
    // can't sneak through.
    syncRuleType() {
        if (!this.hasRuleTypeSelectTarget) return
        const weekly = this.ruleTypeSelectTarget.value === "weekday"
        if (this.hasProductionWrapTarget) this.productionWrapTarget.classList.toggle("hidden", weekly)
        if (this.hasWeekdayWrapTarget) this.weekdayWrapTarget.classList.toggle("hidden", !weekly)
    }
}
