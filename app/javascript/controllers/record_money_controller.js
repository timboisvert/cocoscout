import { Controller } from "@hotwired/stimulus"

// The Record money sheet: the production and its date sit behind two
// switches (off, the menus are hidden and send nothing); the date list
// only shows the chosen production's shows; and the submit button names
// the amount ("Record $412.00").
export default class extends Controller {
    static targets = ["production", "show", "amount", "submit", "forProduction", "productionFields", "forShow", "showFields"]
    static values = { verb: { type: String, default: "Record" } }

    connect() {
        this.toggleProduction()
        this.updateSubmit()
    }

    // The production switch: off clears the production and the date too.
    toggleProduction() {
        if (!this.hasForProductionTarget) return this.filterShows()
        const on = this.forProductionTarget.checked
        this.productionFieldsTarget.classList.toggle("hidden", !on)
        if (!on) {
            if (this.hasProductionTarget) this.productionTarget.value = ""
            if (this.hasForShowTarget) this.forShowTarget.checked = false
        }
        this.toggleShow()
    }

    // The date switch: off clears the date.
    toggleShow() {
        if (this.hasForShowTarget && this.hasShowFieldsTarget) {
            const on = this.forShowTarget.checked
            this.showFieldsTarget.classList.toggle("hidden", !on)
            if (!on && this.hasShowTarget) this.showTarget.value = ""
        }
        this.filterShows()
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
