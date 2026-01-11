import { Controller } from "@hotwired/stimulus"

// Manages the payout scheme form, handling method-specific field visibility
// and building the allocation/distribution JSON from form inputs.
export default class extends Controller {
    static targets = [
        "sharesOptions",
        "perTicketOptions",
        "minimumOption",
        "flatFeeOptions",
        "allocationSection",
        "performerPercentage",
        "housePercentage",
        "allocationJson"
    ]

    connect() {
        this.updateVisibility()
        this.updatePercentages()
    }

    // Called when distribution method changes
    updateMethod() {
        this.updateVisibility()
    }

    // Get the currently selected distribution method
    get selectedMethod() {
        const checked = this.element.querySelector('input[name="rules[distribution][method]"]:checked')
        return checked ? checked.value : "equal"
    }

    // Show/hide method-specific options
    updateVisibility() {
        const method = this.selectedMethod

        // Hide all options first
        if (this.hasSharesOptionsTarget) {
            this.sharesOptionsTarget.classList.add("hidden")
        }
        if (this.hasPerTicketOptionsTarget) {
            this.perTicketOptionsTarget.classList.add("hidden")
        }
        if (this.hasMinimumOptionTarget) {
            this.minimumOptionTarget.classList.add("hidden")
        }
        if (this.hasFlatFeeOptionsTarget) {
            this.flatFeeOptionsTarget.classList.add("hidden")
        }
        if (this.hasAllocationSectionTarget) {
            // Only show allocation section for pool-based methods
            if (["equal", "shares"].includes(method)) {
                this.allocationSectionTarget.classList.remove("hidden")
            } else {
                this.allocationSectionTarget.classList.add("hidden")
            }
        }

        // Show the relevant options
        switch (method) {
            case "shares":
                if (this.hasSharesOptionsTarget) {
                    this.sharesOptionsTarget.classList.remove("hidden")
                }
                break
            case "per_ticket":
                if (this.hasPerTicketOptionsTarget) {
                    this.perTicketOptionsTarget.classList.remove("hidden")
                }
                break
            case "per_ticket_guaranteed":
                if (this.hasPerTicketOptionsTarget) {
                    this.perTicketOptionsTarget.classList.remove("hidden")
                }
                if (this.hasMinimumOptionTarget) {
                    this.minimumOptionTarget.classList.remove("hidden")
                }
                break
            case "flat_fee":
                if (this.hasFlatFeeOptionsTarget) {
                    this.flatFeeOptionsTarget.classList.remove("hidden")
                }
                break
        }
    }

    // Update the performer percentage display when house percentage changes
    updatePercentages() {
        if (!this.hasHousePercentageTarget || !this.hasPerformerPercentageTarget) {
            return
        }

        const housePercent = parseFloat(this.housePercentageTarget.value) || 0
        const performerPercent = Math.max(0, 100 - housePercent)
        this.performerPercentageTarget.textContent = `${performerPercent}%`

        // Update the hidden allocation JSON
        this.updateAllocationJson()
    }

    // Update the allocation JSON hidden field
    updateAllocationJson() {
        if (!this.hasAllocationJsonTarget) {
            return
        }

        const housePercent = parseFloat(this.housePercentageTarget?.value) || 0
        this.allocationJsonTarget.value = JSON.stringify({
            type: "percentage",
            value: housePercent,
            to: "house"
        })
    }
}
