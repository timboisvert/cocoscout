import { Controller } from "@hotwired/stimulus"

// Populates hidden event name field when an event radio button is selected
export default class extends Controller {
  static targets = ["eventName"]

  select(event) {
    const eventName = event.target.dataset.eventName
    if (this.hasEventNameTarget && eventName) {
      this.eventNameTarget.value = eventName
    }
  }
}
