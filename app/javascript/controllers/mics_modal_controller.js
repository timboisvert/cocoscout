import { Controller } from "@hotwired/stimulus"

// Opens a <dialog> by id. Native dialog handles Escape; we also close
// on backdrop click so it behaves like a normal modal.
//
// Usage:
//   <button data-controller="mics-modal"
//           data-action="click->mics-modal#open"
//           data-mics-modal-target-id-value="modal-verify">
//     Verify info
//   </button>
//
//   <dialog id="modal-verify" data-controller="mics-modal"
//           data-action="click->mics-modal#backdropClose">
//     ...form...
//     <button type="button" data-action="click->mics-modal#close">Cancel</button>
//   </dialog>
export default class extends Controller {
  static values = { targetId: String }

  open(e) {
    e.preventDefault()
    const id = this.targetIdValue || e.currentTarget.getAttribute("data-mics-modal-target-id-value")
    const d = id ? document.getElementById(id) : null
    if (d && typeof d.showModal === "function") {
      d.showModal()
    }
  }

  close(e) {
    e?.preventDefault?.()
    const d = this.element.closest("dialog") || this.element
    if (d.close) d.close()
  }

  // Click on dialog's ::backdrop fires with the click target equal to
  // the dialog itself; close in that case.
  backdropClose(e) {
    if (e.target === this.element) {
      this.element.close()
    }
  }
}
