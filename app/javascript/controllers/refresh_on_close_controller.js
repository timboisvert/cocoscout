import { Controller } from "@hotwired/stimulus"

// A sheet whose contents change in place (a frame inside it) while the page
// behind stays as it was: once something has changed, closing the sheet
// refreshes the page, where it is.
//
//   data-controller="modal refresh-on-close"
//   data-action="turbo:frame-load->refresh-on-close#changed"
export default class extends Controller {
    connect() {
        this.stale = false
        this.observer = new MutationObserver(() => this.closed())
        this.observer.observe(this.element, { attributes: true, attributeFilter: ["class"] })
    }

    disconnect() {
        this.observer?.disconnect()
    }

    changed() {
        this.stale = true
    }

    // Closing to hand over to another modal (Staff it opens Add a shift,
    // whose own save reloads the page): no refresh under it.
    settle() {
        this.stale = false
    }

    closed() {
        if (!this.stale || !this.element.classList.contains("hidden")) return

        this.stale = false
        window.Turbo.visit(window.location.href, { action: "replace" })
    }
}
