import { Controller } from "@hotwired/stimulus"

// The lines of a new invoice: add a line, remove one, and keep the total
// and each line's amount current as quantities and prices are typed.
export default class extends Controller {
    static targets = ["lines", "template", "total"]

    connect() { this.recalculate() }

    add(event) {
        event.preventDefault()
        const index = Date.now()
        const html = this.templateTarget.innerHTML.replace(/NEW_LINE/g, index)
        this.linesTarget.insertAdjacentHTML("beforeend", html)
        this.recalculate()
    }

    remove(event) {
        event.preventDefault()
        const row = event.currentTarget.closest("[data-invoice-line]")
        const destroy = row.querySelector("input[name*='_destroy']")
        if (destroy) { destroy.value = "1"; row.classList.add("hidden") } else { row.remove() }
        this.recalculate()
    }

    recalculate() {
        let total = 0
        this.linesTarget.querySelectorAll("[data-invoice-line]").forEach(row => {
            if (row.classList.contains("hidden")) return
            const qty = parseFloat((row.querySelector("[data-qty]")?.value || "1").replace(/[^0-9.]/g, "")) || 0
            const unit = parseFloat((row.querySelector("[data-unit]")?.value || "0").replace(/[^0-9.]/g, "")) || 0
            const amount = Math.round(qty * unit * 100) / 100
            const cell = row.querySelector("[data-amount]")
            if (cell) cell.textContent = amount.toLocaleString("en-US", { style: "currency", currency: "USD" })
            total += amount
        })
        if (this.hasTotalTarget) this.totalTarget.textContent = total.toLocaleString("en-US", { style: "currency", currency: "USD" })
    }
}
