import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="nested-form"
export default class extends Controller {
  static targets = ["children", "template", "bundleTemplate"]

  add(event) {
    event.preventDefault()
    this.insert(this.templateTarget)
  }

  // A second kind of row from its own template (a ticket bundle).
  addBundle(event) {
    event.preventDefault()
    this.insert(this.bundleTemplateTarget)
  }

  insert(template) {
    const html = template.innerHTML.replace(/NEW_CHILD_RECORD/g, new Date().getTime())
    this.childrenTarget.insertAdjacentHTML("beforeend", html)
  }

  remove(event) {
    event.preventDefault()
    const item = event.target.closest(".nested-fields")
    item.querySelector("input[name*='_destroy']").value = "1"
    item.style.display = "none"
  }

  // A saved row goes when the form is saved: mark it, dim it and say so,
  // with Undo. Clicking again (or Undo) keeps it.
  toggleRemove(event) {
    event.preventDefault()
    const item = event.target.closest(".nested-fields")
    const destroy = item.querySelector("input[name*='_destroy']")
    const removing = destroy.value !== "1"
    destroy.value = removing ? "1" : "0"
    item.querySelector("[data-removal-note]")?.classList.toggle("hidden", !removing)
    item.querySelector("[data-removal-fields]")?.classList.toggle("opacity-40", removing)
  }
}
