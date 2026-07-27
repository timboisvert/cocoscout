import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "scopeRadio",
    "scopeField",
    "notifyCheckbox",
    "notifySection",
    "notifyField",
    "cancelForm",
    "confirmMessage",
    "categoryCheckbox",
    "categoryField"
  ]

  static values = {
    eventType: String,
    singleDate: String,
    occurrenceCount: Number,
    futureCount: Number
  }

  toggleScope() {
    // Find the selected radio button
    const selectedRadio = this.scopeRadioTargets.find(r => r.checked)
    const scope = selectedRadio ? selectedRadio.value : "this"

    // Update hidden scope field
    if (this.hasScopeFieldTarget) {
      this.scopeFieldTarget.value = scope
    }

    // Keep the in-page confirm modal's message in sync with the selected scope.
    if (this.hasConfirmMessageTarget) {
      let message
      if (scope === "all") {
        message = `Are you sure you want to cancel all ${this.occurrenceCountValue} occurrences in this series?`
      } else if (scope === "this_and_future") {
        message = `Are you sure you want to cancel this and ${this.futureCountValue - 1} future occurrences?`
      } else {
        message = `Are you sure you want to cancel this ${this.eventTypeValue.toLowerCase()} on ${this.singleDateValue}?`
      }
      this.confirmMessageTarget.textContent = message
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
    // Initialize the confirm modal message for the default scope.
    this.toggleScope()
  }
}
