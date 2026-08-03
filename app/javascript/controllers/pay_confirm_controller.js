import { Controller } from "@hotwired/stimulus"

// Submit-time guardrails for the Pay People form.
//
// 1. Missing-hours check: approved time entries that aren't included in this
//    pay (e.g. a shift approved after someone's hours were added) get flagged —
//    include them with one click, or skip.
// 2. Summary: who's getting paid, how much, and for what, with an acknowledge
//    checkbox and payment-timing info, before the form actually submits.
const MIN_BUSINESS_DAYS = 2
const MAX_BUSINESS_DAYS = 4

export default class extends Controller {
    static targets = ["missingModal", "missingList", "summaryModal",
                      "summaryList", "summaryTotal", "summaryOwed", "summaryOwedAmount",
                      "timing", "ack", "confirmButton"]

    intercept(event) {
        if (this.confirmed) return // acknowledged — let the submit through
        event.preventDefault()

        this.missing = this.collectMissing()
        if (this.missing.length) {
            this.renderMissing()
            this.missingModalTarget.classList.remove("hidden")
        } else {
            this.showSummary()
        }
    }

    // ---- missing hours ------------------------------------------------------

    // Approved-entry checkboxes (in each person's Hours modal) that aren't checked.
    // Rows hidden from the grid (excluded/inactive members) are skipped — their
    // old approved hours shouldn't nag every submit; revealing the person
    // (data-hidden-from-pay flips to "false") brings the check back.
    collectMissing() {
        return this.rows().filter(row => row.dataset.hiddenFromPay !== "true").flatMap(row => {
            const boxes = this.modalBoxesFor(row).filter(cb => !cb.checked)
            if (!boxes.length) return []
            const hours = boxes.reduce((sum, cb) => sum + (parseFloat(cb.dataset.hours) || 0), 0)
            return [{ row, boxes, hours }]
        })
    }

    renderMissing() {
        this.missingListTarget.innerHTML = this.missing.map(m => {
            const name = this.esc(m.row.dataset.memberName || "Staff member")
            const entries = m.boxes.length === 1 ? "1 entry" : `${m.boxes.length} entries`
            return `<div class="flex items-center justify-between gap-3 px-3 py-1.5 bg-amber-50 border border-amber-200 rounded">
                      <span class="font-medium">${name}</span>
                      <span class="text-gray-600">${entries} · ${Math.round(m.hours * 100) / 100}h</span>
                    </div>`
        }).join("")
    }

    includeMissing() {
        // Check the boxes for real — so even if the user cancels the summary
        // step, the hours stay included.
        const memberIds = this.missing.map(m => {
            m.boxes.forEach(cb => { cb.checked = true })
            return m.row.dataset.memberId
        })
        this.dispatchCommit(memberIds)
        this.refreshTotals()
        this.missingModalTarget.classList.add("hidden")
        this.showSummary()
    }

    skipMissing() {
        this.missingModalTarget.classList.add("hidden")
        this.showSummary()
    }

    // ---- summary + acknowledge ----------------------------------------------

    showSummary() {
        const lines = this.rows().map(row => this.rowSummary(row)).filter(Boolean)
        // Total matches the grid footer: only people with a connected bank move money.
        const total = lines.reduce((sum, l) => sum + (l.payable ? l.total : 0), 0)
        // No-bank people's money is still recorded on the run as owed — show it
        // rather than letting it silently vanish from the total.
        const owed = lines.reduce((sum, l) => sum + (l.payable ? 0 : l.total), 0)
        if (this.hasSummaryOwedTarget) {
            this.summaryOwedTarget.classList.toggle("hidden", owed <= 0)
            if (this.hasSummaryOwedAmountTarget) this.summaryOwedAmountTarget.textContent = this.money(owed)
        }

        this.summaryListTarget.innerHTML = lines.length
            ? lines.map(l => `
                <div class="flex items-start justify-between gap-3 py-2">
                  <div class="min-w-0">
                    <div class="text-sm font-medium text-gray-900 truncate">${this.esc(l.name)}</div>
                    <div class="text-xs text-gray-500">${l.parts.map(p => this.esc(p)).join(" · ")}</div>
                  </div>
                  <div class="text-sm font-semibold ${l.payable ? "text-gray-900" : "text-gray-400"} tabular-nums flex-shrink-0">${this.money(l.total)}</div>
                </div>`).join("")
            : '<p class="text-sm text-gray-500 py-2">Nothing to pay yet.</p>'
        this.summaryTotalTarget.textContent = this.money(total)

        this.timingTarget.textContent = this.timingText()
        this.ackTarget.checked = false
        this.confirmButtonTarget.disabled = true
        this.summaryModalTarget.classList.remove("hidden")
    }

    rowSummary(row) {
        const val = f => parseFloat(row.querySelector(`[data-pay-field="${f}"]`)?.value || "0") || 0
        const worked = (parseFloat(row.dataset.workedCents) || 0) / 100
        const workedHours = parseFloat(row.dataset.workedHours) || 0
        const bonus = val("bonus")
        const reimb = val("reimbursement")
        const tips = val("tips")
        const total = worked + bonus + reimb + tips
        if (total <= 0) return null

        const parts = []
        if (worked > 0) parts.push(`${Math.round(workedHours * 100) / 100}h worked · ${this.money(worked)}`)
        if (bonus > 0) parts.push(`${this.money(bonus)} bonus`)
        if (reimb > 0) parts.push(`${this.money(reimb)} reimbursement`)
        if (tips > 0) parts.push(`${this.money(tips)} tips`)
        const payable = row.dataset.payable === "true"
        if (!payable) parts.push("no bank connected — stays owed")
        return { name: row.dataset.memberName || "Staff member", parts, total, payable }
    }

    ackChanged() {
        this.confirmButtonTarget.disabled = !this.ackTarget.checked
    }

    confirm() {
        if (!this.ackTarget.checked) return
        this.confirmed = true
        this.closeAll()
        this.element.requestSubmit()
    }

    // ---- shared -------------------------------------------------------------

    closeAll() {
        this.missingModalTarget.classList.add("hidden")
        this.summaryModalTarget.classList.add("hidden")
    }

    backdropClose(event) {
        if (event.target === this.missingModalTarget || event.target === this.summaryModalTarget) this.closeAll()
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    rows() {
        return Array.from(this.element.querySelectorAll('[data-pay-run-target="row"]'))
    }

    modalBoxesFor(row) {
        const modal = this.element.querySelector(`[data-pay-hours-target="modal"][data-member-id="${row.dataset.memberId}"]`)
        return modal ? Array.from(modal.querySelectorAll("[data-entry-id]")) : []
    }

    dispatchCommit(memberIds) {
        const grid = this.element.querySelector('[data-controller~="pay-hours"]')
        if (grid) grid.dispatchEvent(new CustomEvent("pay-hours:commit", { detail: { memberIds } }))
    }

    refreshTotals() {
        const anyHours = this.element.querySelector('[data-pay-field="hours"]')
        if (anyHours) anyHours.dispatchEvent(new Event("input", { bubbles: true }))
    }

    // "Pay date Fri, Aug 7 — deposits land ≈2–4 business days after you fund &
    // pay the run (est. Aug 11 – Aug 13)."
    timingText() {
        const payday = this.element.querySelector('input[name="payday"]')?.value
        const base = payday ? this.parseLocalDate(payday) : new Date()
        const earliest = this.addBusinessDays(base, MIN_BUSINESS_DAYS)
        const latest = this.addBusinessDays(base, MAX_BUSINESS_DAYS)
        const fmt = d => d.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" })
        return `Pay date ${fmt(base)} — this adds to your open staff pay run; once you fund & pay the run, ` +
               `deposits land about 2–4 business days later (est. ${fmt(earliest)} – ${fmt(latest)}).`
    }

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

    esc(text) {
        const div = document.createElement("div")
        div.textContent = text
        return div.innerHTML
    }

    money(n) {
        return "$" + (Number.isFinite(n) ? n : 0).toFixed(2)
    }
}
