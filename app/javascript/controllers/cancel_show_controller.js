import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "scopeCheckbox",
    "scopeField",
    "notifyCheckbox",
    "notifySection",
    "notifyField",
    "cancelForm",
    "submitButton",
    "categoryCheckbox",
    "categoryField"
  ]

  static values = {
    eventType: String,
    singleDate: String,
    occurrenceCount: Number
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
        this.submitButtonTarget.setAttribute("data-turbo-confirm", `Are you sure you want to cancel all ${this.occurrenceCountValue} occurrences in this series?`)
      } else {
        this.submitButtonTarget.value = `Cancel ${this.eventTypeValue}`
        this.submitButtonTarget.setAttribute("data-turbo-confirm", `Are you sure you want to cancel this ${this.eventTypeValue.toLowerCase()} on ${this.singleDateValue}?`)
      }
    }
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

  updateFormFields() {
    const isNotifyChecked = this.hasNotifyCheckboxTarget && this.notifyCheckboxTarget.checked
    const notifyValue = isNotifyChecked ? "1" : "0"

    // Update hidden fields
    if (this.hasNotifyFieldTarget) {
      this.notifyFieldTarget.value = notifyValue
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
