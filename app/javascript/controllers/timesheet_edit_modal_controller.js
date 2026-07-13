import { Controller } from "@hotwired/stimulus"

// Drives the timesheet edit / re-approve modal on the approved-hours page.
// The modal content lives inside a top-level turbo frame ("timesheet_edit_modal");
// loading a URL into that frame shows the overlay, emptying it hides the overlay.
//
// Two dismissal behaviors:
//   close  — used while editing (nothing changed yet): just empty the frame.
//   reload — used after a save (the entry was kicked back to review): refresh the
//            list so it reflects the new state, whichever way the manager exits.
export default class extends Controller {
  frame() {
    return document.getElementById("timesheet_edit_modal")
  }

  close() {
    const frame = this.frame()
    if (frame) frame.innerHTML = ""
  }

  closeOnBackdrop(event) {
    if (event.target === this.element) this.close()
  }

  reload() {
    Turbo.visit(window.location.href, { action: "replace" })
  }

  reloadOnBackdrop(event) {
    if (event.target === this.element) this.reload()
  }

  stopPropagation(event) {
    event.stopPropagation()
  }
}
