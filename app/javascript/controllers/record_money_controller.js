import { Controller } from "@hotwired/stimulus"

// The Record money sheet: the "A particular date" list only shows the
// chosen production's shows, and the submit button names the amount
// ("Record $412.00").
export default class extends Controller {
    static targets = ["production", "show", "amount", "submit"]
    static values = { verb: { type: String, default: "Record" } }

    connect() {
        this.filterShows()
        this.updateSubmit()
    }

    filterShows() {
        if (!this.hasProductionTarget || !this.hasShowTarget) return
        const productionId = this.productionTarget.value
        let keepSelection = false
        Array.from(this.showTarget.options).forEach(option => {
            if (!option.value) return
            const fits = productionId !== "" && option.dataset.production === productionId
            option.hidden = !fits
            option.disabled = !fits
            if (fits && option.selected) keepSelection = true
        })
        if (!keepSelection) this.showTarget.value = ""
        this.showTarget.disabled = productionId === ""
    }

    updateSubmit() {
        if (!this.hasSubmitTarget || !this.hasAmountTarget) return
        const raw = (this.amountTarget.value || "").replace(/[^0-9.]/g, "")
        const amount = parseFloat(raw)
        const label = this.submitTarget.querySelector("[data-record-money-label]") || this.submitTarget
        if (isNaN(amount) || amount <= 0) {
            label.textContent = this.verbValue
        } else {
            label.textContent = `${this.verbValue} ${amount.toLocaleString("en-US", { style: "currency", currency: "USD" })}`
        }
    }
}
