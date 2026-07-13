import { Controller } from "@hotwired/stimulus"

// Generic help pop-up. Put data-controller="help-modal" on a wrapper that
// contains both the trigger(s) and the modal. Triggers use
// data-action="click->help-modal#open"; the modal element carries
// data-help-modal-target="modal". Toggles the `hidden` class.
export default class extends Controller {
  static targets = ["modal"]

  open(event) {
    if (event) event.preventDefault()
    this.modalTarget.classList.remove("hidden")
  }

  close() {
    this.modalTarget.classList.add("hidden")
  }

  closeOnBackdrop(event) {
    if (event.target === this.modalTarget) this.close()
  }

  stop(event) {
    event.stopPropagation()
  }
}
