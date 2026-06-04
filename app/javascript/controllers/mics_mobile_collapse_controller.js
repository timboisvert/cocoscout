import { Controller } from "@hotwired/stimulus"

// Collapses a `<details>` element on small screens and forces it open
// on lg+ (1024px+). Used to hide sidebar filters by default on mobile
// so the user can scroll straight to the listing.
export default class extends Controller {
  connect() {
    this.sync = this.sync.bind(this)
    this.sync()
    window.addEventListener("resize", this.sync)
  }

  disconnect() {
    window.removeEventListener("resize", this.sync)
  }

  sync() {
    if (window.innerWidth >= 1024) {
      this.element.open = true
    }
  }
}
