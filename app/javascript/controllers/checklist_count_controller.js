import { Controller } from "@hotwired/stimulus"

// A checklist's running count ("6 of 9 here"), kept up as boxes are ticked.
export default class extends Controller {
  static targets = ["box", "count"]

  update() {
    this.countTarget.textContent = this.boxTargets.filter((box) => box.checked).length
  }
}
