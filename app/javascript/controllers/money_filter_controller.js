import { Controller } from "@hotwired/stimulus"

// Controls hiding/showing non-revenue events in the money page list
export default class extends Controller {
    static targets = ["toggle", "showRow"]
    static values = {
        hideNonRevenue: { type: Boolean, default: true }
    }

    connect() {
        // Load saved preference from localStorage
        const saved = localStorage.getItem("hideNonRevenueEvents")
        if (saved !== null) {
            this.hideNonRevenueValue = saved === "true"
        }
        this.updateToggleState()
        this.filterRows()
    }

    toggle() {
        this.hideNonRevenueValue = !this.hideNonRevenueValue
        localStorage.setItem("hideNonRevenueEvents", this.hideNonRevenueValue)
        this.updateToggleState()
        this.filterRows()
    }

    updateToggleState() {
        if (this.hasToggleTarget) {
            const toggle = this.toggleTarget
            if (this.hideNonRevenueValue) {
                toggle.classList.add("bg-pink-600")
                toggle.classList.remove("bg-gray-200")
                toggle.querySelector("[data-toggle-dot]").classList.add("translate-x-5")
                toggle.querySelector("[data-toggle-dot]").classList.remove("translate-x-0")
            } else {
                toggle.classList.remove("bg-pink-600")
                toggle.classList.add("bg-gray-200")
                toggle.querySelector("[data-toggle-dot]").classList.remove("translate-x-5")
                toggle.querySelector("[data-toggle-dot]").classList.add("translate-x-0")
            }
        }
    }

    filterRows() {
        this.showRowTargets.forEach(row => {
            const isNonRevenue = row.dataset.nonRevenue === "true"
            if (this.hideNonRevenueValue && isNonRevenue) {
                row.classList.add("hidden")
            } else {
                row.classList.remove("hidden")
            }
        })
    }
}
