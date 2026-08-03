import { Controller } from "@hotwired/stimulus"

// Live deposit estimate for the pay-date field on the Pay People screen.
// The chosen date is the day the manager plans to fund & pay the run; deposits
// land ~2-4 business days after that. Past dates are invalid — we flag them and
// hide the estimate (the server rejects them too).
const MIN_BUSINESS_DAYS = 2
const MAX_BUSINESS_DAYS = 4

export default class extends Controller {
    static targets = ["date", "estimate", "error"]

    connect() {
        this.update()
    }

    update() {
        const raw = this.dateTarget.value
        if (!raw) {
            this.showError("Pick a pay date.")
            return
        }

        const chosen = this.parseLocalDate(raw)
        const today = new Date()
        today.setHours(0, 0, 0, 0)

        if (chosen < today) {
            this.showError("That date has passed — pick today or a later date.")
            return
        }

        const earliest = this.addBusinessDays(chosen, MIN_BUSINESS_DAYS)
        const latest = this.addBusinessDays(chosen, MAX_BUSINESS_DAYS)
        this.showEstimate(
            `Paid ${this.sameDay(chosen, today) ? "today" : "on " + this.format(chosen)}, ` +
            `deposits should land ${this.format(earliest)} – ${this.format(latest)} (2–4 business days).`
        )
    }

    showError(message) {
        if (this.hasErrorTarget) {
            this.errorTarget.textContent = message
            this.errorTarget.classList.remove("hidden")
        }
        if (this.hasEstimateTarget) this.estimateTarget.classList.add("hidden")
        this.dateTarget.classList.add("border-red-400")
    }

    showEstimate(text) {
        if (this.hasErrorTarget) this.errorTarget.classList.add("hidden")
        if (this.hasEstimateTarget) {
            this.estimateTarget.textContent = text
            this.estimateTarget.classList.remove("hidden")
        }
        this.dateTarget.classList.remove("border-red-400")
    }

    // "2026-08-03" → local-midnight Date (avoids the UTC off-by-one of new Date(str))
    parseLocalDate(value) {
        const [y, m, d] = value.split("-").map(Number)
        return new Date(y, m - 1, d)
    }

    addBusinessDays(date, count) {
        const out = new Date(date)
        let added = 0
        while (added < count) {
            out.setDate(out.getDate() + 1)
            const day = out.getDay()
            if (day !== 0 && day !== 6) added++
        }
        return out
    }

    sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
    }

    format(date) {
        return date.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" })
    }
}
