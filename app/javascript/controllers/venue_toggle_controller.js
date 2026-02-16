import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "venueFields", "onlineFields"]

  connect() {
    // Initial state is set via hidden class in the template
  }

  toggle() {
    const isOnline = this.checkboxTarget.checked

    if (this.hasVenueFieldsTarget) {
      if (isOnline) {
        this.venueFieldsTarget.classList.add("hidden")
      } else {
        this.venueFieldsTarget.classList.remove("hidden")
      }
    }

    if (this.hasOnlineFieldsTarget) {
      if (isOnline) {
        this.onlineFieldsTarget.classList.remove("hidden")
      } else {
        this.onlineFieldsTarget.classList.add("hidden")
      }
    }
  }
}
