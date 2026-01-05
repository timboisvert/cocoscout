import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "scopeCheckbox",
    "scopeField",
    "notifyCheckbox",
    "notifySection",
    "notifyField",
    "emailSubject",
    "emailSubjectField",
    "emailDraftForm",
    "emailBodyField",
    "cancelForm",
    "submitButton",
    "categoryCheckbox",
    "categoryField"
  ]

  static values = {
    eventType: String,
    singleDate: String,
    occurrenceCount: Number,
    singleSubject: String,
    allSubject: String,
    singleBody: String,
    allBody: String
  }

  toggleScope() {
    const isAll = this.hasScopeCheckboxTarget && this.scopeCheckboxTarget.checked

    // Update hidden scope field
    if (this.hasScopeFieldTarget) {
      this.scopeFieldTarget.value = isAll ? "all" : "this"
    }

    // Update button text and confirmation message
    if (this.hasSubmitButtonTarget) {
      if (isAll) {
        this.submitButtonTarget.value = `Cancel All ${this.occurrenceCountValue} ${this.eventTypeValue}s`
        this.submitButtonTarget.dataset.turboConfirm = `Are you sure you want to cancel all ${this.occurrenceCountValue} occurrences in this series?`
      } else {
        this.submitButtonTarget.value = `Cancel ${this.eventTypeValue}`
        this.submitButtonTarget.dataset.turboConfirm = `Are you sure you want to cancel this ${this.eventTypeValue.toLowerCase()} on ${this.singleDateValue}?`
      }
    }

    // Update email subject and body if notify is enabled
    this.updateEmailContent()
  }

  toggleNotifySection() {
    const isChecked = this.hasNotifyCheckboxTarget && this.notifyCheckboxTarget.checked

    if (this.hasNotifySectionTarget) {
      if (isChecked) {
        this.notifySectionTarget.classList.remove("hidden")
      } else {
        this.notifySectionTarget.classList.add("hidden")
      }
    }

    this.updateFormFields()
  }

  updateEmailContent() {
    const isAll = this.hasScopeCheckboxTarget && this.scopeCheckboxTarget.checked

    // Update subject
    if (this.hasEmailSubjectTarget) {
      this.emailSubjectTarget.value = isAll ? this.allSubjectValue : this.singleSubjectValue
    }

    // Update body in Trix editor
    if (this.hasEmailDraftFormTarget) {
      const trixEditor = this.emailDraftFormTarget.querySelector("trix-editor")
      if (trixEditor && trixEditor.editor) {
        const newContent = isAll ? this.allBodyValue : this.singleBodyValue
        trixEditor.editor.loadHTML(newContent)
      }
    }
  }

  updateFormFields() {
    const isNotifyChecked = this.hasNotifyCheckboxTarget && this.notifyCheckboxTarget.checked
    const notifyValue = isNotifyChecked ? "1" : "0"

    // Get subject from input
    let subject = ""
    if (this.hasEmailSubjectTarget) {
      subject = this.emailSubjectTarget.value
    }

    // Get email body content from Trix editor
    let emailContent = ""
    if (this.hasEmailDraftFormTarget) {
      const trixEditor = this.emailDraftFormTarget.querySelector("trix-editor")
      if (trixEditor) {
        // Get the HTML content from the hidden input
        const inputElement = this.emailDraftFormTarget.querySelector("input[type='hidden'][id$='_body']")
        if (inputElement) {
          emailContent = inputElement.value
        }
      }
    }

    // Update hidden fields
    if (this.hasNotifyFieldTarget) {
      this.notifyFieldTarget.value = notifyValue
    }
    if (this.hasEmailSubjectFieldTarget) {
      this.emailSubjectFieldTarget.value = subject
    }
    if (this.hasEmailBodyFieldTarget) {
      this.emailBodyFieldTarget.value = emailContent
    }
  }

  // Toggle category hidden fields based on checkbox state
  toggleCategory(event) {
    const checkbox = event.target
    const category = checkbox.dataset.category

    // Find the corresponding hidden field
    const hiddenField = this.categoryFieldTargets.find(field => field.dataset.category === category)

    if (hiddenField) {
      if (checkbox.checked) {
        // Re-enable the hidden field by setting its value
        hiddenField.disabled = false
        hiddenField.value = category
      } else {
        // Disable the hidden field so it's not submitted
        hiddenField.disabled = true
      }
    }
  }

  // Hook into form submission to ensure fields are updated
  connect() {
    if (this.hasCancelFormTarget) {
      this.cancelFormTarget.addEventListener("submit", () => this.updateFormFields())
    }
  }
}
