import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["display", "form"]

  showEdit(event) {
    if (event) event.preventDefault()
    this.displayTarget.classList.add("hidden")
    this.formTarget.classList.remove("hidden")
  }

  hideEdit(event) {
    if (event) event.preventDefault()
    this.formTarget.classList.add("hidden")
    this.displayTarget.classList.remove("hidden")
  }
}
