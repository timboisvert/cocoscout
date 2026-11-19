import { Controller } from "@hotwired/stimulus"

// A visual asset specification's size (Organization settings → Visual
// Assets): the DPI is asked for only when the size is in inches, for print.
export default class extends Controller {
  static targets = ["unit", "dpi"]

  change() {
    this.dpiTarget.classList.toggle("hidden", this.unitTarget.value !== "inches")
  }
}
