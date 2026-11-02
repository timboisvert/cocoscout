import { Controller } from "@hotwired/stimulus"

// Books → Bank rules: the rule modal, filled from a line's Rule link (its
// words and direction) or a rule's Edit (everything, and the form then
// changes that rule), with a live count of the lines waiting it fits.
// Direction decides which category list shows (income or spending);
// Ignore hides the record fields. Sits on the page wrapper beside
// bank-record. The modal's own modal controller closes it.
//
// Rule link / Edit: data-action="click->bank-rule#open" with
// data-bank-rule-{id,contains,direction,kind,category,counterparty,production,on-import}-param.
export default class extends Controller {
    static targets = ["modal", "rulesModal", "form", "method", "title", "contains", "matches", "recordFields", "categoryOut", "categoryIn",
        "counterparty", "counterpartyLabel", "production", "onImport"]

    disconnect() {
        clearTimeout(this.timer)
    }

    // The Rules modal closes like any other, except that a suggestion taken
    // changed lines on the page behind it: then the page reloads.
    closeRules() {
        if (!this.hasRulesModalTarget) return
        if (this.rulesModalTarget.querySelector("[data-bank-rules-changed]")) {
            window.location.reload()
            return
        }
        this.rulesModalTarget.classList.add("hidden")
    }

    closeRulesOnBackdrop(event) {
        if (event.target === event.currentTarget) this.closeRules()
    }

    open(event) {
        event.preventDefault()
        const p = event.params || {}
        const editing = !!p.id
        this.formTarget.action = editing ? this.formTarget.action.replace(/\/rules(\/\d+)?$/, `/rules/${p.id}`) : this.formTarget.action.replace(/\/rules\/\d+$/, "/rules")
        this.methodTarget.value = editing ? "patch" : "post"
        this.titleTarget.textContent = editing ? "Change this rule" : "New rule"

        this.containsTarget.value = p.contains || ""
        this.check("bank_rule[direction]", p.direction || "out")
        this.check("bank_rule[action]", p.kind || "record")
        this.counterpartyTarget.value = p.counterparty || ""
        if (this.hasProductionTarget) this.productionTarget.value = p.production ? String(p.production) : ""
        this.onImportTarget.checked = p.onImport === undefined || p.onImport === null || p.onImport === true || p.onImport === "true"
        this.refresh()
        const category = this.activeCategory()
        if (category) category.value = p.category && Array.from(category.options).some(o => o.value === p.category) ? p.category : ""

        if (this.hasRulesModalTarget) this.rulesModalTarget.classList.add("hidden")
        this.modalTarget.classList.remove("hidden")
        this.preview()
        this.containsTarget.focus()
    }

    // Direction → which category list; action → whether the record fields show.
    refresh() {
        const direction = this.checked("bank_rule[direction]")
        const ignore = this.checked("bank_rule[action]") === "ignore"
        this.recordFieldsTarget.classList.toggle("hidden", ignore)
        const income = direction === "in"
        this.categoryInTarget.classList.toggle("hidden", !income)
        this.categoryOutTarget.classList.toggle("hidden", income)
        this.categoryInTarget.querySelector("select").disabled = ignore || !income
        this.categoryOutTarget.querySelector("select").disabled = ignore || income
        this.counterpartyLabelTarget.textContent = income ? "From" : "Paid to"
        if (!ignore && direction === "any") this.check("bank_rule[direction]", "out")
        this.preview()
    }

    // How many lines waiting the phrase fits, a moment after typing stops.
    preview() {
        clearTimeout(this.timer)
        this.timer = setTimeout(() => this.fetchPreview(), 250)
    }

    async fetchPreview() {
        const contains = this.containsTarget.value.trim()
        if (!contains) { this.matchesTarget.textContent = ""; return }
        const url = new URL(this.formTarget.dataset.bankRulePreviewUrlValue, window.location.origin)
        url.searchParams.set("contains", contains)
        url.searchParams.set("direction", this.checked("bank_rule[direction]"))
        try {
            const response = await fetch(url, { headers: { "Accept": "application/json" } })
            if (!response.ok) return
            const data = await response.json()
            if (data.count === 0) {
                this.matchesTarget.textContent = "Fits none of the lines waiting. It will still run on statements brought in later."
            } else {
                const samples = data.samples.length ? ` Such as: ${data.samples.join("; ")}.` : ""
                this.matchesTarget.textContent = `Fits ${data.count} ${data.count === 1 ? "line" : "lines"} waiting.${samples}`
            }
        } catch (_) {
            this.matchesTarget.textContent = ""
        }
    }

    activeCategory() {
        const income = this.checked("bank_rule[direction]") === "in"
        return (income ? this.categoryInTarget : this.categoryOutTarget).querySelector("select")
    }

    check(name, value) {
        const radio = this.formTarget.querySelector(`[name="${name}"][value="${value}"]`)
        if (radio) radio.checked = true
    }

    checked(name) {
        const radio = this.formTarget.querySelector(`[name="${name}"]:checked`)
        return radio ? radio.value : ""
    }
}
