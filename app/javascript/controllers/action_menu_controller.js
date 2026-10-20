import { Controller } from "@hotwired/stimulus"

// The shared ⋯ menu (shared/_action_menu): its dropdown from sm up, the
// same items in a bottom sheet on a phone (shared/_sheet).
export default class extends Controller {
  static values = { sheetId: String }

  open(event) {
    event.preventDefault()
    event.stopPropagation()
    if (window.matchMedia("(min-width: 640px)").matches) {
      const dropdown = this.application.getControllerForElementAndIdentifier(this.element, "dropdown")
      dropdown?.toggle(event)
    } else {
      const sheet = document.getElementById(this.sheetIdValue)
      sheet?.classList.remove("hidden")
    }
  }
}
