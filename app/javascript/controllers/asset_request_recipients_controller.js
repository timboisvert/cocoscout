import { Controller } from "@hotwired/stimulus"

// The request sheet's "Send the request" stays inactive until someone is
// chosen: a ticked person, or an address typed in (Tim, 2026-11-19).
// "Copy the link without emailing" needs nobody, so it is left alone.
export default class extends Controller {
  static targets = ["choice", "others", "send"]

  connect() {
    this.refresh()
  }

  refresh() {
    const ticked = this.choiceTargets.some((box) => box.checked)
    const typed = this.hasOthersTarget && this.othersTarget.value.trim() !== ""
    this.sendTargets.forEach((button) => { button.disabled = !(ticked || typed) })
  }
}
