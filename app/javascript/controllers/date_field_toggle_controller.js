import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="date-field-toggle"
export default class extends Controller {
  static targets = [ "checkbox", "field" ]

  connect() {
    this.updateFieldState()
  }

  toggle() {
    this.updateFieldState()
  }

  updateFieldState() {
    if (this.checkboxTarget.checked) {
      // Open-ended: disable and clear the field
      this.fieldTarget.disabled = true
      this.fieldTarget.value = ""
      this.fieldTarget.classList.add("bg-gray-100", "cursor-not-allowed")
    } else {
      // Closed: enable the field
      this.fieldTarget.disabled = false
      this.fieldTarget.classList.remove("bg-gray-100", "cursor-not-allowed")
    }
  }
}
