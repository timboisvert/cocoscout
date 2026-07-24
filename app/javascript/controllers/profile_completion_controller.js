import { Controller } from "@hotwired/stimulus"

// Drives the dashboard "complete your info" panel for talent-pool members.
// The contact and headshot gaps open a modal; the payment gap is a link to the
// bank-setup page. Modals submit normal forms and redirect back here.
export default class extends Controller {
    static targets = ["contactModal", "headshotModal"]

    open(event) {
        if (event) event.preventDefault()
        const which = event.currentTarget.dataset.gap
        this.modalFor(which)?.classList.remove("hidden")
    }

    close(event) {
        if (event) event.preventDefault()
        this.allModals().forEach(m => m.classList.add("hidden"))
    }

    backdropClose(event) {
        if (event.target.dataset.profileCompletionModal !== undefined) {
            event.target.classList.add("hidden")
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    // ----- private -----

    modalFor(which) {
        if (which === "contact" && this.hasContactModalTarget) return this.contactModalTarget
        if (which === "headshot" && this.hasHeadshotModalTarget) return this.headshotModalTarget
        return null
    }

    allModals() {
        return [
            this.hasContactModalTarget && this.contactModalTarget,
            this.hasHeadshotModalTarget && this.headshotModalTarget
        ].filter(Boolean)
    }
}
