import { Controller } from "@hotwired/stimulus"

// The add-to-payout-run picker: checkboxes decide who rides the run, and the
// footer total/acknowledgment updates live so the manager confirms exactly
// what they're committing to fund. Unchecking someone keeps them off the run
// (they stay owed, to be paid another way).
export default class extends Controller {
    static targets = ["checkbox", "total", "ack", "submit"]

    connect() {
        this.recalc()
    }

    recalc() {
        let total = 0
        let count = 0
        let noBank = 0
        let noBankCents = 0
        this.checkboxTargets.forEach(box => {
            if (!box.checked) return
            total += parseInt(box.dataset.cents, 10) || 0
            count += 1
            if (box.dataset.bankReady !== "true") {
                noBank += 1
                noBankCents += parseInt(box.dataset.cents, 10) || 0
            }
        })

        if (this.hasTotalTarget) this.totalTarget.textContent = this.money(total)
        if (this.hasAckTarget) {
            this.ackTarget.textContent = count === 0
                ? "No one selected — nothing will be added."
                : `You'll fund ${this.money(total)} for ${count} ${count === 1 ? "person" : "people"}` +
                  (noBank > 0 ? `, including ${this.money(noBankCents)} for ${noBank} without a bank connected — that money rides the run until they connect.` : ".")
        }
        if (this.hasSubmitTarget) this.submitTarget.disabled = count === 0
    }

    money(cents) {
        return "$" + (cents / 100).toFixed(2)
    }
}
