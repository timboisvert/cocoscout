import { Controller } from "@hotwired/stimulus"

// Amend review: when new events collide with existing bookings, the Apply
// button stays locked behind a "View the conflict" modal. Acknowledging inside
// the modal sets the force_overlap flag on the apply form and unlocks Apply.
export default class extends Controller {
  static targets = ["modal", "flag", "submit"]

  connect() {
    // There are conflicts (this controller only mounts when there are), so lock
    // Apply until the user acknowledges them.
    this.lock()
  }

  open() {
    this.modalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  close() {
    this.modalTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  closeOnBackdrop(event) {
    if (event.target === event.currentTarget) this.close()
  }

  toggle(event) {
    if (event.target.checked) {
      this.flagTarget.value = "1"
      this.unlock()
    } else {
      this.flagTarget.value = ""
      this.lock()
    }
  }

  lock() {
    const button = this.submitButton()
    if (!button) return
    button.disabled = true
    button.classList.add("opacity-50", "cursor-not-allowed")
  }

  unlock() {
    const button = this.submitButton()
    if (!button) return
    button.disabled = false
    button.classList.remove("opacity-50", "cursor-not-allowed")
  }

  submitButton() {
    if (!this.hasSubmitTarget) return null
    return this.submitTarget.tagName === "BUTTON"
      ? this.submitTarget
      : this.submitTarget.querySelector("button")
  }
}
