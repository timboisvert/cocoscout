import { Controller } from "@hotwired/stimulus"

// Drives the dashboard "complete your info" panel for talent-pool members.
// Each gap (contact / headshot / payment) opens its own modal. Modals submit
// normal forms to My::ProfileCompletionController and redirect back here.
export default class extends Controller {
    static targets = ["contactModal", "headshotModal", "paymentModal", "venmoFields", "zelleFields"]

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

    // Toggle Venmo vs Zelle field groups in the payment modal.
    switchPaymentMethod(event) {
        const method = event.currentTarget.value
        if (this.hasVenmoFieldsTarget) this.venmoFieldsTarget.classList.toggle("hidden", method !== "venmo")
        if (this.hasZelleFieldsTarget) this.zelleFieldsTarget.classList.toggle("hidden", method !== "zelle")
    }

    // ----- private -----

    modalFor(which) {
        if (which === "contact" && this.hasContactModalTarget) return this.contactModalTarget
        if (which === "headshot" && this.hasHeadshotModalTarget) return this.headshotModalTarget
        if (which === "payment" && this.hasPaymentModalTarget) return this.paymentModalTarget
        return null
    }

    allModals() {
        return [
            this.hasContactModalTarget && this.contactModalTarget,
            this.hasHeadshotModalTarget && this.headshotModalTarget,
            this.hasPaymentModalTarget && this.paymentModalTarget
        ].filter(Boolean)
    }
}
