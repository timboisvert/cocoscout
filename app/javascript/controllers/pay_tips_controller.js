import { Controller } from "@hotwired/stimulus"

// Tips from settled days (Settle up) waiting on Pay People, the way approved
// hours wait: "Pull in tips" writes each person's shares onto their tips (or
// cash tips) worksheet as one day each, carries the share ids so they leave
// the waiting pool when the run is submitted, and lets the tips-worksheet and
// pay-run controllers relabel and retotal from the inputs as they always do.
export default class extends Controller {
    static targets = ["row", "bar"]

    pullAll(event) {
        if (event) event.preventDefault()
        this.rowTargets.forEach(row => this.pull(row))
        if (this.hasBarTarget) this.barTarget.classList.add("hidden")
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
