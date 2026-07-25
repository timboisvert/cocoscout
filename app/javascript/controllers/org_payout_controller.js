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
}
