import { Controller } from "@hotwired/stimulus"
import { parseMoney, sanitizeMoneyField } from "controllers/lib/money_input"

// A per-day worksheet for a tips (or cash-tips) field: enter (date, amount) rows,
// see a live total, and "Use total" writes the sum into the field. The breakdown
// is stored as hidden inputs in the row (so it persists via the form draft), and
// re-read the next time the worksheet opens.
//
// The grid has no tips text box — the button IS the field, exactly like Hours:
// "Add tips" when there's nothing there, "3 days · $120.00" once there is. That
// keeps the day-by-day breakdown and the total from ever disagreeing, which a
// free-text box next to a worksheet link couldn't promise.
export default class extends Controller {
    static targets = ["modal", "title", "rows", "subtotal", "template", "button"]

    connect() {
        this.syncAll()
    }

    open(event) {
        if (event) event.preventDefault()
        const d = event.currentTarget.dataset
        this.memberId = d.memberId
        this.fieldName = d.fieldName          // "tips_sheet" | "cash_tips_sheet"
        this.fieldInputId = d.fieldInputId    // the pay input to fill
        this.holderId = d.holderId            // hidden-input holder for the breakdown
        if (this.hasTitleTarget) this.titleTarget.textContent = d.title || "Worksheet"

        this.rowsTarget.innerHTML = ""
        const existing = this.readHolder()
        if (existing.length) existing.forEach(({ date, amount }) => this.appendRow(date, amount))
        else this.appendRow("", "")
        this.recalc()
        this.modalTarget.classList.remove("hidden")
    }

    addRow(event) {
        if (event) event.preventDefault()
        this.appendRow("", "")
    }

    removeRow(event) {
        event.currentTarget.closest("[data-row]")?.remove()
        this.recalc()
    }

    recalc(event) {
        // A pasted "$25" or "1,200" must not read as zero — scrub the field as
        // it's typed/pasted so only digits and dots remain.
        if (event?.target) sanitizeMoneyField(event.target)
        const total = this.rowData().reduce((a, r) => a + r.amount, 0)
        if (this.hasSubtotalTarget) this.subtotalTarget.textContent = "$" + total.toFixed(2)
    }

    useTotal(event) {
        if (event) event.preventDefault()
        const rows = this.rowData()
        const total = rows.reduce((a, r) => a + r.amount, 0)

        const field = document.getElementById(this.fieldInputId)
        if (field) {
            field.value = (Math.round(total * 100) / 100).toFixed(2)
            field.dispatchEvent(new Event("input", { bubbles: true })) // fires pay-run#recalc for tips
        }
        const holder = document.getElementById(this.holderId)
        if (holder) {
            holder.innerHTML = rows
                .map(r => `<input type="hidden" name="lines[${this.memberId}][${this.fieldName}][]" value="${this.escape(r.date)}|${r.amount}">`)
                .join("")
        }
        this.syncButton(this.buttonFor(this.fieldInputId))
        this.close()
    }

    // Re-derive every button's label from the form (runs on connect and on any
    // grid input, so a restored draft labels itself).
    syncAll() {
        this.buttonTargets.forEach(button => this.syncButton(button))
    }

    syncButton(button) {
        if (!button) return
        const amount = parseMoney(document.getElementById(button.dataset.fieldInputId)?.value)
        const days = document.getElementById(button.dataset.holderId)?.querySelectorAll("input").length || 0
        const money = "$" + amount.toFixed(2)

        // A draft saved before the worksheet existed can carry an amount with no
        // days behind it — show the money rather than pretending it's empty.
        if (amount <= 0) button.textContent = button.dataset.emptyLabel || "Add"
        else if (days > 0) button.textContent = `${days} ${days === 1 ? "day" : "days"} · ${money}`
        else button.textContent = money
    }

    buttonFor(fieldInputId) {
        return this.buttonTargets.find(b => b.dataset.fieldInputId === fieldInputId)
    }

    close(event) {
        if (event) event.preventDefault()
        this.modalTarget.classList.add("hidden")
    }

    backdropClose(event) {
        if (event.target === this.modalTarget) this.close(event)
    }

    stopPropagation(event) { event.stopPropagation() }

    // ---- helpers ----

    appendRow(date, amount) {
        const node = this.templateTarget.content.firstElementChild.cloneNode(true)
        node.querySelector('[data-cell="date"]').value = date || ""
        node.querySelector('[data-cell="amount"]').value = amount || ""
        this.rowsTarget.appendChild(node)
    }

    rowData() {
        return Array.from(this.rowsTarget.querySelectorAll("[data-row]"))
            .map(r => ({
                date: r.querySelector('[data-cell="date"]').value,
                amount: parseMoney(r.querySelector('[data-cell="amount"]').value)
            }))
            .filter(r => r.amount > 0)
    }

    readHolder() {
        const holder = document.getElementById(this.holderId)
        if (!holder) return []
        return Array.from(holder.querySelectorAll("input")).map(i => {
            const [date, amount] = i.value.split("|")
            return { date: date || "", amount: amount || "" }
        })
    }

    escape(str) {
        return String(str == null ? "" : str).replace(/"/g, "&quot;")
    }
}
