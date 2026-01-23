import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form"]

  showForm(event) {
    if (event) event.preventDefault()
    this.formTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  hideForm(event) {
    if (event) event.preventDefault()
    this.formTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  stopPropagation(event) {
    event.stopPropagation()
  }
}
