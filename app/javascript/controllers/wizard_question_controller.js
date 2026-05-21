import { Controller } from "@hotwired/stimulus"

// Drives the wizard's Add/Edit Question modal. Handles:
//  - showing/hiding the Options textarea based on selected question type
//  - opening the modal in "new" mode (blank form, POST to add endpoint)
//  - opening the modal in "edit" mode (populated form, PATCH to update endpoint)
export default class extends Controller {
    static targets = [
        "modal", "form", "title", "submitButton", "methodInput",
        "typeSelect", "optionsSection", "optionsTextarea", "optionsError",
        "textInput", "requiredCheckbox"
    ]
    static values = {
        needsOptionsKeys: Array,
        addUrl: String,
        updateUrlTemplate: String
    }

    connect() {
        this.update()
    }

    typeChanged() {
        this.update()
    }

    update() {
        if (!this.hasTypeSelectTarget || !this.hasOptionsSectionTarget) return
        const key = this.typeSelectTarget.value
        if (this.needsOptionsKeysValue.includes(key)) {
            this.optionsSectionTarget.classList.remove("hidden")
        } else {
            this.optionsSectionTarget.classList.add("hidden")
            this.clearOptionsError()
        }
    }

    // Form-submit guard. If an options-needing type is selected but the
    // textarea has nothing usable, block the submit and surface the error
    // inline instead of bouncing through a server-side flash.
    validateBeforeSubmit(event) {
        if (!this.hasTypeSelectTarget) return
        const key = this.typeSelectTarget.value
        if (!this.needsOptionsKeysValue.includes(key)) return

        const lines = this.hasOptionsTextareaTarget
            ? this.optionsTextareaTarget.value.split("\n").map(s => s.trim()).filter(s => s.length > 0)
            : []
        if (lines.length === 0) {
            event.preventDefault()
            this.showOptionsError()
        } else {
            this.clearOptionsError()
        }
    }

    showOptionsError() {
        if (this.hasOptionsErrorTarget) this.optionsErrorTarget.classList.remove("hidden")
        if (this.hasOptionsTextareaTarget) {
            this.optionsTextareaTarget.classList.remove("border-gray-300")
            this.optionsTextareaTarget.classList.add("border-pink-500")
            this.optionsTextareaTarget.focus()
        }
    }

    clearOptionsError() {
        if (this.hasOptionsErrorTarget) this.optionsErrorTarget.classList.add("hidden")
        if (this.hasOptionsTextareaTarget) {
            this.optionsTextareaTarget.classList.remove("border-pink-500")
            this.optionsTextareaTarget.classList.add("border-gray-300")
        }
    }

    openForNew(event) {
        if (event) event.preventDefault()
        this.resetForm()
        if (this.hasFormTarget && this.hasAddUrlValue) {
            this.formTarget.action = this.addUrlValue
        }
        if (this.hasMethodInputTarget) this.methodInputTarget.value = "post"
        if (this.hasTitleTarget) this.titleTarget.textContent = "Add Question"
        if (this.hasSubmitButtonTarget) {
            const span = this.submitButtonTarget.querySelector("span")
            if (span) span.textContent = "Add Question"
        }
        this.openModal()
    }

    openForEdit(event) {
        if (event) event.preventDefault()
        const btn = event.currentTarget
        const index = btn.dataset.questionIndex
        const text = btn.dataset.questionText || ""
        const type = btn.dataset.questionType || "textarea"
        const required = btn.dataset.questionRequired === "true"
        let options = []
        try {
            options = JSON.parse(btn.dataset.questionOptions || "[]")
        } catch (e) {
            options = []
        }

        if (this.hasTextInputTarget) this.textInputTarget.value = text
        if (this.hasTypeSelectTarget) this.typeSelectTarget.value = type
        if (this.hasRequiredCheckboxTarget) this.requiredCheckboxTarget.checked = required
        if (this.hasOptionsTextareaTarget) this.optionsTextareaTarget.value = options.join("\n")
        this.clearOptionsError()
        this.update()

        if (this.hasFormTarget && this.hasUpdateUrlTemplateValue) {
            this.formTarget.action = this.updateUrlTemplateValue.replace(":index", index)
        }
        if (this.hasMethodInputTarget) this.methodInputTarget.value = "patch"
        if (this.hasTitleTarget) this.titleTarget.textContent = "Edit Question"
        if (this.hasSubmitButtonTarget) {
            const span = this.submitButtonTarget.querySelector("span")
            if (span) span.textContent = "Save Question"
        }

        this.openModal()
    }

    openModal() {
        if (this.hasModalTarget) this.modalTarget.classList.remove("hidden")
    }

    close(event) {
        if (event) event.preventDefault()
        if (this.hasModalTarget) this.modalTarget.classList.add("hidden")
    }

    closeOnBackdrop(event) {
        if (event.target === this.modalTarget) this.close(event)
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    resetForm() {
        if (this.hasTextInputTarget) this.textInputTarget.value = ""
        if (this.hasTypeSelectTarget) this.typeSelectTarget.value = "textarea"
        if (this.hasRequiredCheckboxTarget) this.requiredCheckboxTarget.checked = false
        if (this.hasOptionsTextareaTarget) this.optionsTextareaTarget.value = ""
        this.clearOptionsError()
        this.update()
    }
}
