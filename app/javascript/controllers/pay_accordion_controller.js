import { Controller } from "@hotwired/stimulus"
import { parseMoney } from "controllers/lib/money_input"

// Mobile accordion for the Pay People cards. Each person starts collapsed
// showing just their name + a live summary of anything entered (hours, bonus,
// tips… and the computed total). Tapping a header opens that person's fields
// and closes everyone else's. Desktop (lg+) renders the classic table and this
// controller stays out of the way.
export default class extends Controller {
    static targets = ["row"]

    connect() {
        this.refreshAll()
    }

    toggle(event) {
        if (this.isDesktop()) return
        if (event.target.closest("input, button, a")) return

        const row = event.currentTarget.closest("[data-pay-accordion-target='row']")
        const opening = row.dataset.open !== "true"
        this.rowTargets.forEach(r => this.setOpen(r, false)) // exclusive: close everyone
        if (opening) this.setOpen(row, true)
    }

    // Recompute every row's collapsed summary (fired by any input in the grid,
    // including the draft restore and pulled hours).
    refreshAll() {
        this.rowTargets.forEach(row => this.refresh(row))
    }

    setOpen(row, open) {
        row.dataset.open = open ? "true" : "false"
        row.querySelectorAll("[data-acc-field]").forEach(td => {
            td.classList.toggle("hidden", !open)
            td.classList.toggle("flex", open)
        })
        const chevron = row.querySelector("[data-acc-chevron]")
        if (chevron) chevron.classList.toggle("rotate-180", open)
        this.refresh(row)
    }

    refresh(row) {
        const summary = row.querySelector("[data-acc-summary]")
        if (!summary) return

        const val = f => parseMoney(row.querySelector(`[data-pay-field="${f}"]`)?.value)
        const money = n => `$${(n % 1 === 0) ? n : n.toFixed(2)}`

        const parts = []
        // Worked hours = included entries + ad-hoc (the Hours modal keeps the
        // row dataset in sync); fall back to the raw input for safety.
        const hours = parseFloat(row.dataset.workedHours) || val("hours")
        if (hours > 0) parts.push(`${hours}h`)
        if (val("bonus") > 0) parts.push(`${money(val("bonus"))} bonus`)
        if (val("reimbursement") > 0) parts.push(`${money(val("reimbursement"))} reimb.`)
        if (val("tips") > 0) parts.push(`${money(val("tips"))} tips`)
        const cash = parseMoney(row.querySelector('input[name$="[cash_tips]"]')?.value)
        if (cash > 0) parts.push(`${money(cash)} cash tips`)

        const total = row.querySelector("[data-pay-total]")?.textContent?.trim()
        if (parts.length && total && total !== "$0.00") parts.push(`→ ${total}`)

        summary.textContent = parts.join(" · ")
        // Show only when collapsed and there's something to show (lg:hidden keeps
        // it out of the desktop table regardless).
        summary.classList.toggle("hidden", parts.length === 0 || row.dataset.open === "true")
    }

    isDesktop() {
        return window.matchMedia("(min-width: 1024px)").matches
    }
}
