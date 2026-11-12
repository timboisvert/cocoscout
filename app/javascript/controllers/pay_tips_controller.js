import { Controller } from "@hotwired/stimulus"

// Tips from settled days (Settle up) waiting on Pay People, the way approved
// hours wait: "Pull in tips" writes each person's shares onto their tips (or
// cash tips) worksheet as one day each, carries the share ids so they leave
// the waiting pool when the run is submitted, and lets the tips-worksheet and
// pay-run controllers relabel and retotal from the inputs as they always do.
export default class extends Controller {
    static targets = ["row", "bar", "pullModal", "pullCheckbox"]

    // After the saved draft is restored (pay-draft, on the same element,
    // connects first): the bar shows only while a share is still to pull.
    connect() {
        setTimeout(() => this.sync(), 0)
    }

    // "Pull in tips" opens the same kind of window as "Pull in approved
    // hours": who has tips waiting, checked, to confirm (Tim, 2026-11-11).
    openPull(event) {
        if (event) event.preventDefault()
        if (!this.hasPullModalTarget) return this.pullAll()
        this.pullModalTarget.classList.remove("hidden")
        document.body.classList.add("overflow-hidden")
    }

    closePull() {
        if (!this.hasPullModalTarget) return
        this.pullModalTarget.classList.add("hidden")
        document.body.classList.remove("overflow-hidden")
    }

    pullSelectAll() { this.pullCheckboxTargets.forEach(cb => { cb.checked = true }) }
    pullSelectNone() { this.pullCheckboxTargets.forEach(cb => { cb.checked = false }) }

    pullConfirm() {
        const chosen = new Set(this.pullCheckboxTargets.filter(cb => cb.checked).map(cb => String(cb.dataset.memberId)))
        this.rowTargets.filter(row => chosen.has(String(row.dataset.memberId))).forEach(row => this.pull(row))
        this.closePull()
        this.sync()
    }

    pullAll(event) {
        if (event) event.preventDefault()
        this.rowTargets.forEach(row => this.pull(row))
        this.sync()
    }

    // "Pull in tips" is offered only while some waiting share isn't on its
    // person's row yet (Tim, 2026-11-11: it came back on every visit).
    sync() {
        if (!this.hasBarTarget) return
        const left = this.rowTargets.some(row => {
            let shares = []
            try { shares = JSON.parse(row.dataset.tipsWaiting || "[]") } catch (_) { return false }
            if (!shares.length || row.dataset.hiddenFromPay === "true") return false
            const holder = document.getElementById(`pay-tip-shares-${row.dataset.memberId}`)
            const pulled = new Set(Array.from(holder ? holder.querySelectorAll("input") : []).map(input => String(input.value)))
            return shares.some(s => !pulled.has(String(s.id)))
        })
        this.barTarget.classList.toggle("hidden", !left)
    }

    pull(row) {
        let shares = []
        try { shares = JSON.parse(row.dataset.tipsWaiting || "[]") } catch (_) { return }
        if (!shares.length || row.dataset.hiddenFromPay === "true") return
        const id = row.dataset.memberId

        const holder = document.getElementById(`pay-tip-shares-${id}`)
        if (holder) {
            holder.innerHTML = shares
                .map(s => `<input type="hidden" name="lines[${id}][tip_share_ids][]" value="${s.id}">`)
                .join("")
        }
        this.fill(id, shares.filter(s => s.method === "payout"), `pay-tips-${id}`, `pay-tips-sheet-${id}`, "tips_sheet")
        this.fill(id, shares.filter(s => s.method === "cash"), `pay-cashtips-${id}`, `pay-cashtips-sheet-${id}`, "cash_tips_sheet")
    }

    // Replaces what the worksheet held: the settled days are the record now,
    // and a day typed by hand earlier would double up with its share.
    fill(id, shares, fieldId, holderId, fieldName) {
        if (!shares.length) return
        const total = shares.reduce((sum, s) => sum + Number(s.amount), 0)
        const holder = document.getElementById(holderId)
        if (holder) {
            holder.innerHTML = shares
                .map(s => `<input type="hidden" name="lines[${id}][${fieldName}][]" value="${this.escape(s.date)}|${s.amount}">`)
                .join("")
        }
        const field = document.getElementById(fieldId)
        if (field) {
            field.value = total.toFixed(2)
            field.dispatchEvent(new Event("input", { bubbles: true }))
        }
    }

    escape(str) {
        return String(str == null ? "" : str).replace(/"/g, "&quot;")
    }
}
