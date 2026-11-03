import { Controller } from "@hotwired/stimulus"

// Books → Bank: Record it opens the Record this line modal on the page,
// filled from the row (the amount, the date, the bank's description, and
// what was recorded for the same payee last time). Saving answers with a
// Turbo Stream that swaps the row and resets the modal, so the page never
// leaves or reloads. The modal's own modal controller closes it.
//
// Sits on the page wrapper:
//   data-controller="bank-record"
// Targets: modal (the modal element), form (one wrapper per kind, with
// data-kind="in" or "out"), summary (the line in words at the top).
// A Record it button: data-action="click->bank-record#open" with
// data-bank-record-{kind,amount,on,memo,line,category,counterparty,summary}-param.
export default class extends Controller {
    static targets = ["modal", "form", "summary"]

    disconnect() {
        document.removeEventListener("keydown", this.escape)
    }

    open(event) {
        event.preventDefault()
        const p = event.params
        let form = null
        this.formTargets.forEach(wrapper => {
            const mine = wrapper.dataset.kind === p.kind
            wrapper.classList.toggle("hidden", !mine)
            if (mine) form = wrapper
        })
        if (!form) return

        this.fill(form, "money_record[amount]", p.amount)
        this.fill(form, "money_record[on]", p.on)
        this.fill(form, "money_record[memo]", p.memo)
        this.fill(form, "money_record[counterparty]", p.counterparty || "")
        this.fill(form, "bank_line", p.line)
        this.fill(form, "money_record[production_id]", "")
        const categoryInput = form.querySelector('[name="money_record[category_key]"]')
        const category = categoryInput && this.application.getControllerForElementAndIdentifier(categoryInput.closest('[data-controller~="category-picker"]'), "category-picker")
        if (category) category.set(p.category || "")
        const via = form.querySelector('[name="money_record[via]"][value="bank"]')
        if (via) via.checked = true
        const amount = form.querySelector('[name="money_record[amount]"]')
        if (amount) amount.dispatchEvent(new Event("input", { bubbles: true }))
        const forProduction = form.querySelector('[data-record-money-target="forProduction"]')
        if (forProduction) {
            forProduction.checked = false
            forProduction.dispatchEvent(new Event("change", { bubbles: true }))
        }
        form.querySelectorAll("[data-bank-record-errors]").forEach(el => el.remove())

        if (this.hasSummaryTarget) this.summaryTarget.textContent = p.summary || ""
        this.modalTarget.classList.remove("hidden")
        this.escape = this.escape || (e => { if (e.key === "Escape") this.close() })
        document.addEventListener("keydown", this.escape)
        if (category) category.focus()
    }

    close() {
        if (this.hasModalTarget) this.modalTarget.classList.add("hidden")
        document.removeEventListener("keydown", this.escape)
    }

    fill(form, name, value) {
        const field = form.querySelector(`[name="${name}"]`)
        if (field) field.value = value == null ? "" : value
    }
}
