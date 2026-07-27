import { Controller } from "@hotwired/stimulus"

// Keeps the submit button disabled until a radio inside the controller element
// is chosen. Put data-controller="require-choice" on the form, mark the submit
// button with data-require-choice-target="submit" (and start it disabled), and
// fire change->require-choice#update on the radios.
export default class extends Controller {
  static targets = ["submit"]

  connect() {
    this.update()
  }

  update() {
    if (!this.hasSubmitTarget) return
    const chosen = this.element.querySelector('input[type="radio"]:checked')
    this.submitTarget.disabled = !chosen
  }
}
