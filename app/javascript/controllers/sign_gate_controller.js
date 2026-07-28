import { Controller } from "@hotwired/stimulus"

// Keeps the sign button disabled until the signer has typed a name AND checked
// the agreement box. Put data-controller="sign-gate" on the form, mark the name
// input, the agree checkbox, and the submit button as targets, and fire
// input/change->sign-gate#update on the inputs.
export default class extends Controller {
  static targets = ["name", "agree", "submit"]

  connect() {
    this.update()
  }

  update() {
    if (!this.hasSubmitTarget) return
    const named = this.hasNameTarget && this.nameTarget.value.trim().length > 0
    const agreed = this.hasAgreeTarget && this.agreeTarget.checked
    this.submitTarget.disabled = !(named && agreed)
  }
}
