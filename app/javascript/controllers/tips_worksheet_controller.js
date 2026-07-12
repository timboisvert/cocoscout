import { Controller } from "@hotwired/stimulus"

// A per-day worksheet for a tips (or cash-tips) field: enter (date, amount) rows,
// see a live total, and "Use total" writes the sum into the field. The breakdown
// is stored as hidden inputs in the row (so it persists via the form draft), and
// re-read the next time the worksheet opens.
export default class extends Controller {
    static targets = ["modal", "title", "rows", "subtotal", "template"]

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

    recalc() {
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
        this.close()
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
                amount: parseFloat(r.querySelector('[data-cell="amount"]').value) || 0
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
