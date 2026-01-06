import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle", "content"]

  connect() {
    // Initial state is set via hidden class in the template
  }

  toggle(event) {
    const isChecked = this.toggleTarget.checked
    
    if (this.hasContentTarget) {
      if (isChecked) {
        this.contentTarget.classList.remove("hidden")
      } else {
        this.contentTarget.classList.add("hidden")
      }
    }
  }
}
