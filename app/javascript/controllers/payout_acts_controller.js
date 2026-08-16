import { Controller } from "@hotwired/stimulus"

// Drives the "How many acts?" modal on an act-based payout. Mirrors the
// server-side rules (PayoutScheme.act_amount) so each row shows what the
// entered count is worth before you commit to calculating.
export default class extends Controller {
    static targets = ["modal", "input", "amount", "total", "applyAllInput"]
    static values = {
        mode: { type: String, default: "tiers" },
        rate: { type: Number, default: 0 },
        tiers: { type: Array, default: [] },
        actRates: { type: Array, default: [] },
        additionalRate: { type: Number, default: 0 }
    }

    connect() {
        // The calculate action bounces back here with the modal already open, so
        // lock the page behind it the same way opening it by hand would.
        if (this.hasModalTarget && !this.modalTarget.classList.contains("hidden")) {
            document.body.classList.add("overflow-hidden")
        }
        this.update()
    }

    disconnect() {
        document.body.classList.remove("overflow-hidden")
    }

    open(event) {
        if (event) event.preventDefault()
        if (!this.hasModalTarget) return
        this.modalTarget.classList.remove("hidden")
        document.body.classList.add("overflow-hidden")
        this.update()
    }

    close(event) {
        if (event) event.preventDefault()
        if (!this.hasModalTarget) return
        this.modalTarget.classList.add("hidden")
        document.body.classList.remove("overflow-hidden")

        // Drop ?enter_acts=1 so a refresh doesn't reopen what was just dismissed.
        const url = new URL(window.location.href)
        if (url.searchParams.has("enter_acts")) {
            url.searchParams.delete("enter_acts")
            window.history.replaceState({}, "", url)
        }
    }

    closeOnBackdrop(event) {
        if (event.target === this.modalTarget) this.close()
    }

    stop(event) {
        event.stopPropagation()
    }

    // Set every row to the same count — most nights everyone did the same number.
    applyAll(event) {
        if (event) event.preventDefault()
        if (!this.hasApplyAllInputTarget) return

        const count = this.parseCount(this.applyAllInputTarget.value)
        this.inputTargets.forEach(input => { input.value = count })
        this.update()
    }

    update() {
        let total = 0

        this.inputTargets.forEach((input, index) => {
            const amount = this.amountFor(this.parseCount(input.value))
            total += amount
            const amountEl = this.amountTargets[index]
            if (amountEl) amountEl.textContent = this.formatCurrency(amount)
        })

        if (this.hasTotalTarget) this.totalTarget.textContent = this.formatCurrency(total)
    }

    amountFor(count) {
        if (count <= 0) return 0

        if (this.modeValue === "simple") {
            return Math.round(this.rateValue * count * 100) / 100
        }

        if (this.modeValue === "schedule") {
            // Each act is worth its own amount and they add up; anything past
            // the end of the schedule is worth the "additional" rate.
            const rates = [...this.actRatesValue].sort((a, b) => Number(a.act) - Number(b.act))
            let total = 0
            for (let n = 1; n <= count; n++) {
                const row = rates[n - 1]
                total += row ? Number(row.amount) : this.additionalRateValue
            }
            return Math.round(total * 100) / 100
        }

        // Tiers read as "N or more acts pays $X" — take the highest one reached.
        const reached = this.tiersValue
            .filter(tier => Number(tier.acts) > 0 && Number(tier.acts) <= count)
            .sort((a, b) => Number(a.acts) - Number(b.acts))
            .pop()

        return reached ? Math.round(Number(reached.amount) * 100) / 100 : 0
    }

    parseCount(value) {
        const count = parseInt(value, 10)
        return Number.isFinite(count) && count > 0 ? count : 0
    }

    formatCurrency(amount) {
        return `$${amount.toFixed(2)}`
    }
}
