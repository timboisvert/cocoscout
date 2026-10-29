import { Controller } from "@hotwired/stimulus"

// Keeps the submit button disabled until every acknowledgement box inside the
// controller element is checked. Put data-controller="acknowledge-gate" on the
// form, mark the boxes data-acknowledge-gate-target="box" with
// change->acknowledge-gate#update, and the button data-acknowledge-gate-target="submit".
//
// Another lock on the same button (contract-conflict marks its lock with
// cursor-not-allowed) stays in force, and its unlock can't get past this one:
// the form won't submit while a box is unchecked.
export default class extends Controller {
  static targets = ["box", "submit"]

  connect() {
    this.guard = (event) => { if (!this.agreed()) event.preventDefault() }
    this.element.addEventListener("submit", this.guard)
    this.update()
  }

  disconnect() {
    this.element.removeEventListener("submit", this.guard)
  }

  update() {
    const agreed = this.agreed()
    this.submitTargets.forEach((button) => {
      button.disabled = !agreed || button.classList.contains("cursor-not-allowed")
    })
  }

  agreed() {
    return this.boxTargets.every((box) => box.checked)
  }
}
