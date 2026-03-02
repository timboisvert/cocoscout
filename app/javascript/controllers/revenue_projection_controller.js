import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "priceLow", "priceHigh", "ticketsLow", "ticketsHigh", "grossPreview", "sharePreview"]
    static values = { share: Number }

    connect() {
        this.calculate()
    }

    openModal() {
        this.modalTarget.classList.remove("hidden")
        document.body.classList.add("overflow-hidden")
        this.calculate()
    }

    closeModal() {
        this.modalTarget.classList.add("hidden")
        document.body.classList.remove("overflow-hidden")
    }

    calculate() {
        const priceLow = parseFloat(this.priceLowTarget?.value) || 0
        const priceHigh = parseFloat(this.priceHighTarget?.value) || 0
        const ticketsLow = parseInt(this.ticketsLowTarget?.value) || 0
        const ticketsHigh = parseInt(this.ticketsHighTarget?.value) || 0

        const grossLow = priceLow * ticketsLow
        const grossHigh = priceHigh * ticketsHigh

        const sharePercent = this.shareValue / 100
        const shareLow = grossLow * sharePercent
        const shareHigh = grossHigh * sharePercent

        if (this.hasGrossPreviewTarget) {
            this.grossPreviewTarget.textContent = `${this.formatCurrency(grossLow)} - ${this.formatCurrency(grossHigh)}`
        }
        if (this.hasSharePreviewTarget) {
            this.sharePreviewTarget.textContent = `${this.formatCurrency(shareLow)} - ${this.formatCurrency(shareHigh)}`
        }
    }

    formatCurrency(amount) {
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            minimumFractionDigits: 0,
            maximumFractionDigits: 0
        }).format(amount)
    }

    submitForm(event) {
        // Form submits normally, modal will close on page reload
    }
}
