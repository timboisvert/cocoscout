import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["payModal", "sessionPicker", "customAmount", "paymentInfoForm"]

    // Payment type radio toggle (course detail page)
    typeChanged(event) {
        const type = event.target.value

        if (this.hasSessionPickerTarget) {
            this.sessionPickerTarget.classList.toggle("hidden", type !== "per_session")
        }
        if (this.hasCustomAmountTarget) {
            this.customAmountTarget.classList.toggle("hidden", type !== "custom")
        }
    }

    // Pay modal
    showPayModal(event) {
        event.preventDefault()
        if (this.hasPayModalTarget) {
            this.payModalTarget.classList.remove("hidden")
            document.body.classList.add("overflow-hidden")
        }
    }

    hidePayModal(event) {
        if (event) event.preventDefault()
        if (this.hasPayModalTarget) {
            this.payModalTarget.classList.add("hidden")
            document.body.classList.remove("overflow-hidden")
        }
    }

    // Payment info form toggle
    showPaymentInfoForm(event) {
        event.preventDefault()
        if (this.hasPaymentInfoFormTarget) {
            this.paymentInfoFormTarget.classList.toggle("hidden")
        }
    }

    // Open Venmo deep link (mirrors payment_actions_controller)
    openVenmo(event) {
        event.preventDefault()
        const button = event.currentTarget
        const handle = (button.dataset.venmoHandle || "").replace(/^@/, "")
        const amount = button.dataset.venmoAmount
        const note = button.dataset.venmoNote || ""

        const venmoUrl = `venmo://paycharge?txn=pay&recipients=${encodeURIComponent(handle)}&amount=${encodeURIComponent(amount)}&note=${encodeURIComponent(note)}`
        const webUrl = `https://venmo.com/${encodeURIComponent(handle)}?txn=pay&amount=${encodeURIComponent(amount)}&note=${encodeURIComponent(note)}`

        window.location.href = venmoUrl
        setTimeout(() => {
            window.open(webUrl, '_blank')
        }, 1500)
    }
}
