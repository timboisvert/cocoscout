import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="nested-form"
export default class extends Controller {
  static targets = ["children", "template"]

  add(event) {
    event.preventDefault()
    const template = this.templateTarget.innerHTML.replace(
      /NEW_CHILD_RECORD/g,
      new Date().getTime()
    )
    this.childrenTarget.insertAdjacentHTML("beforeend", template)
  }

  remove(event) {
    event.preventDefault()
    const item = event.target.closest(".nested-fields")
    item.querySelector("input[name*='_destroy']").value = "1"
    item.style.display = "none"
  }
}
