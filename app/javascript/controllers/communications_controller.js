import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "modalContent", "individualsSection", "sendToAllField", "recipientList"]

  openModal(event) {
    event.preventDefault()
    this.modalTarget.classList.remove("hidden")
    document.body.style.overflow = "hidden"
  }

  closeModal() {
    this.modalTarget.classList.add("hidden")
    document.body.style.overflow = ""
  }

  closeModalOnBackdrop(event) {
    if (event.target === this.modalTarget) {
      this.closeModal()
    }
  }

  stopPropagation(event) {
    event.stopPropagation()
  }

  toggleRecipientType(event) {
    const value = event.target.value

    if (value === "all") {
      this.individualsSectionTarget.classList.add("hidden")
      this.sendToAllFieldTarget.value = "1"
    } else {
      this.individualsSectionTarget.classList.remove("hidden")
      this.sendToAllFieldTarget.value = "0"
    }
  }

  toggleRecipientList(event) {
    event.preventDefault()
    if (this.hasRecipientListTarget) {
      this.recipientListTarget.classList.toggle("hidden")
      // Update button text
      const button = event.currentTarget
      button.textContent = this.recipientListTarget.classList.contains("hidden") ? "Show" : "Hide"
    }
  }
}
