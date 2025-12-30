import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="date-field-toggle"
export default class extends Controller {
  static targets = ["field", "link", "hiddenField"]
  static values = { default: { type: String, default: "hide" } } // "hide" = open-ended by default, "show" = has date by default

  connect() {
    // The visible field gets the value from Rails form helper, so use that as source of truth
    const initialValue = this.fieldTarget.value

    // Sync hidden field with visible field
    if (initialValue) {
      this.hiddenFieldTarget.value = initialValue
      this.savedValue = initialValue
    } else {
      this.savedValue = ""
    }

    // Determine initial state based on default value or field value
    if (this.defaultValue === "show") {
      // Default to showing the date field (not open-ended)
      this.isOpenEnded = false
    } else {
      // Default to checking if field has a value
      this.isOpenEnded = !initialValue || initialValue.trim() === ""
    }
    this.updateFieldState()

    // Add event listener to sync visible field changes to hidden field
    this.fieldTarget.addEventListener('input', () => this.syncToHiddenField())
    this.fieldTarget.addEventListener('change', () => this.syncToHiddenField())
  }

  syncToHiddenField() {
    if (!this.fieldTarget.disabled) {
      this.hiddenFieldTarget.value = this.fieldTarget.value
    }
  }

  toggle(event) {
    event.preventDefault()

    if (!this.isOpenEnded) {
      // About to make it open-ended, save the current value first
      if (this.fieldTarget.value && this.fieldTarget.value.trim() !== "") {
        this.savedValue = this.fieldTarget.value
      }
    }

    this.isOpenEnded = !this.isOpenEnded
    this.updateFieldState()
  }

  updateFieldState() {
    if (this.isOpenEnded) {
      // Open-ended: disable and clear the field
      this.fieldTarget.disabled = true
      this.fieldTarget.value = ""
      this.hiddenFieldTarget.value = ""
      this.fieldTarget.classList.add("bg-gray-100", "cursor-not-allowed", "text-gray-500")
      this.linkTarget.textContent = "Set a closing date/time"
    } else {
      // Closed: enable the field and restore previous value if available
      this.fieldTarget.disabled = false
      if (this.savedValue) {
        this.fieldTarget.value = this.savedValue
        this.hiddenFieldTarget.value = this.savedValue
      }
      this.fieldTarget.classList.remove("bg-gray-100", "cursor-not-allowed", "text-gray-500")
      this.linkTarget.textContent = "Make open-ended"
    }
  }
}
