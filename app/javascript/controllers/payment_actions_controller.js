import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bulkModal"]

  showBulkModal(event) {
    event.preventDefault()
    this.bulkModalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  hideBulkModal(event) {
    if (event) event.preventDefault()
    this.bulkModalTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  // Close modal on escape key
  connect() {
    this.boundHandleKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.boundHandleKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandleKeydown)
  }

  handleKeydown(event) {
    if (event.key === "Escape" && !this.bulkModalTarget.classList.contains("hidden")) {
      this.hideBulkModal()
    }
  }

  // Close modal when clicking backdrop
  closeOnBackdrop(event) {
    if (event.target === this.bulkModalTarget) {
      this.hideBulkModal()
    }
  }
}
