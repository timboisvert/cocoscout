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
        additionalRate: { type: Number, default: 0 },
        // How a show role's pay (data-role-pay on the row) combines with act
        // pay: both | role_only | higher | flat | table (PayoutScheme::ROLE_STACKINGS).
        stacking: { type: String, default: "both" },
        // The all-in figure(s) for a role holder who also performs — "flat"
        // pays roleWithActsAmount, "table" reads roleWithActsTiers like the
        // main tiers table.
        roleWithActsAmount: { type: Number, default: 0 },
        roleWithActsTiers: { type: Array, default: [] },
        roleWithActsAdditionalRate: { type: Number, default: 0 }
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

    // Act-based production: put every row back to what the lineup says
    // (each input carries its lineup count in data-lineup-count).
    resetToLineup(event) {
        if (event) event.preventDefault()
        this.inputTargets.forEach(input => {
            if (input.dataset.lineupCount === undefined) return
            input.value = this.parseCount(input.dataset.lineupCount)
        })
        this.update()
    }

    update() {
        let total = 0

        this.inputTargets.forEach((input, index) => {
            const amount = this.lineAmountFor(input)
            total += amount
            const amountEl = this.amountTargets[index]
            if (amountEl) amountEl.textContent = this.formatCurrency(amount)
        })

        if (this.hasTotalTarget) this.totalTarget.textContent = this.formatCurrency(total)
    }

    // Act pay for the row's count, plus the show roles it holds, combined the
    // way the calculation says (mirrors PayoutCalculator#per_act_line).
    lineAmountFor(input) {
        const count = this.parseCount(input.value)
        const actPay = this.amountFor(count)
        if (input.dataset.rolePriced !== "true") return actPay

        const rolePay = Number(input.dataset.rolePay) || 0
        if (this.stackingValue === "role_only") return rolePay
        if (this.stackingValue === "higher") return Math.max(rolePay, actPay)
        if (this.stackingValue === "flat") return count > 0 ? this.roleWithActsAmountValue : rolePay
        if (this.stackingValue === "table") {
            return count > 0 ? this.tierAmount(count, this.roleWithActsTiersValue, this.roleWithActsAdditionalRateValue) : rolePay
        }
        return Math.round((rolePay + actPay) * 100) / 100
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

        return this.tierAmount(count, this.tiersValue, this.additionalRateValue)
    }

    // Tiers: each row is the total for that many acts — take the highest row
    // reached. Past the last row, every further act adds the beyond rate
    // (when there is one). Shared by the main table and the role holder's.
    tierAmount(count, rows, additionalRate) {
        if (count <= 0) return 0
        const tiers = rows
            .filter(tier => Number(tier.acts) > 0)
            .sort((a, b) => Number(a.acts) - Number(b.acts))
        const reached = tiers.filter(tier => Number(tier.acts) <= count).pop()
        if (!reached) return 0

        let amount = Number(reached.amount)
        const last = tiers[tiers.length - 1]
        if (reached === last && count > Number(last.acts)) {
            amount += additionalRate * (count - Number(last.acts))
        }
        return Math.round(amount * 100) / 100
    }

    parseCount(value) {
        const count = parseInt(value, 10)
        return Number.isFinite(count) && count > 0 ? count : 0
    }

    formatCurrency(amount) {
        return `$${amount.toFixed(2)}`
    }
}
