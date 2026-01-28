import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["feeInput"]

    connect() {
        this.updateSettlement()
    }

    updateSettlement() {
        const selectedRadio = this.element.querySelector('input[name="settlement_type"]:checked')
        const isFlatFee = selectedRadio?.value === "flat_fee"

        if (this.hasFeeInputTarget) {
            const input = this.feeInputTarget.querySelector('input')
            if (input) {
                input.disabled = !isFlatFee
                if (!isFlatFee) {
                    input.value = ""
                }
            }
        }
    }
}
