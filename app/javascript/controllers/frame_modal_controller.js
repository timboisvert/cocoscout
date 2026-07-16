import { Controller } from "@hotwired/stimulus"

// Generic modal rendered inside a top-level turbo frame. Loading a URL into the
// frame shows the overlay; closing empties the frame, which hides it. Put
// data-controller="frame-modal" on the overlay element inside the frame.
export default class extends Controller {
  connect() {
    this.keyHandler = (e) => { if (e.key === "Escape") this.close() }
    document.addEventListener("keydown", this.keyHandler)
  }

  disconnect() {
    document.removeEventListener("keydown", this.keyHandler)
  }

  close() {
    const frame = this.element.closest("turbo-frame")
    if (frame) frame.innerHTML = ""
  }

  closeOnBackdrop(event) {
    if (event.target === this.element) this.close()
  }

  stop(event) {
    event.stopPropagation()
  }
}
