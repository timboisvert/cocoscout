import { Controller } from "@hotwired/stimulus"

// Books → Bank → Rules: the rule page (Tim, 2026-11-03, no longer a modal).
// Direction decides which category picker shows (income or spending);
// Ignore hides the record fields. As the phrase is typed, "What it
// catches" lists the lines waiting the rule fits, what they add up to,
// and whether the lines already dealt with agree (BankRules.preview).
//
// On the form: data-controller="bank-rule" data-bank-rule-preview-url-value
// Targets: contains, matches (the one-line summary), list (the lines),
// agree (the lines dealt with), recordFields, categoryOut, categoryIn,
// counterpartyLabel, submit.
export default class extends Controller {
    static targets = ["contains", "matches", "list", "agree", "recordFields", "categoryOut", "categoryIn", "counterpartyLabel", "submit"]
    static values = { previewUrl: String }

    connect() {
        this.refresh()
    }

    disconnect() {
        clearTimeout(this.timer)
    }

    // Direction → which category list; action → whether the record fields show.
    refresh() {
        const direction = this.checked("bank_rule[direction]")
        const ignore = this.checked("bank_rule[action]") === "ignore"
        this.recordFieldsTarget.classList.toggle("hidden", ignore)
        const income = direction === "in"
        this.categoryInTarget.parentElement.classList.toggle("hidden", !income)
        this.categoryOutTarget.parentElement.classList.toggle("hidden", income)
        this.picker(this.categoryInTarget)?.disable(ignore || !income)
        this.picker(this.categoryOutTarget)?.disable(ignore || income)
        this.counterpartyLabelTarget.textContent = income ? "From" : "Paid to"
        if (!ignore && direction === "any") this.check("bank_rule[direction]", "out")
        this.preview()
    }

    // A moment after typing stops.
    preview() {
        clearTimeout(this.timer)
        this.timer = setTimeout(() => this.fetchPreview(), 250)
    }

    async fetchPreview() {
        const contains = this.containsTarget.value.trim()
        if (!contains) { this.show(null); return }
        const url = new URL(this.previewUrlValue, window.location.origin)
        url.searchParams.set("contains", contains)
        url.searchParams.set("direction", this.checked("bank_rule[direction]"))
        url.searchParams.set("rule_action", this.checked("bank_rule[action]"))
        url.searchParams.set("category_key", this.activeCategory()?.value || "")
        try {
            const response = await fetch(url, { headers: { "Accept": "application/json" } })
            if (response.ok) this.show(await response.json())
        } catch (_) {
            this.show(null)
        }
    }

    show(data) {
        this.listTarget.innerHTML = ""
        this.agreeTarget.classList.add("hidden")
        if (!data) {
            this.matchesTarget.textContent = "Type a phrase to see the lines waiting it fits."
            this.submitTarget.querySelector("span").textContent = "Save and apply"
            return
        }
        const n = data.count
        if (n === 0) {
            this.matchesTarget.textContent = "Fits none of the lines waiting. It will still run on statements brought in later."
            this.submitTarget.querySelector("span").textContent = "Save"
        } else {
            const span = data.from === data.to ? data.from : `${data.from} to ${data.to}`
            this.matchesTarget.innerHTML = `<span class="font-semibold text-gray-900 tabular-nums">${n} ${n === 1 ? "line" : "lines"} waiting</span> <span class="text-gray-500">· ${this.money(data.total_cents)} · ${span}</span>`
            this.submitTarget.querySelector("span").textContent = `Save and apply to ${n} ${n === 1 ? "line" : "lines"}`
            data.lines.forEach(line => {
                const li = document.createElement("li")
                li.className = "px-5 py-2 flex gap-3"
                li.innerHTML = `<span class="w-14 flex-none text-gray-500 tabular-nums"></span><span class="flex-1 min-w-0 truncate text-gray-700"></span><span class="tabular-nums font-semibold"></span>`
                li.children[0].textContent = line.on
                li.children[1].textContent = line.description
                li.children[1].title = line.description
                li.children[2].textContent = this.money(line.amount_cents)
                this.listTarget.appendChild(li)
            })
            if (n > data.lines.length) {
                const li = document.createElement("li")
                li.className = "px-5 py-2 text-gray-500"
                li.textContent = `… ${n - data.lines.length} more`
                this.listTarget.appendChild(li)
            }
        }
        if (data.agree || data.disagree) {
            const parts = []
            if (data.agree) parts.push(`<span class="font-medium text-green-700">Agrees</span> with ${data.agree} ${data.agree === 1 ? "line" : "lines"} you already dealt with.`)
            if (data.disagree) parts.push(`<span class="font-medium text-amber-700">${data.disagree} ${data.disagree === 1 ? "line" : "lines"}</span> you dealt with by hand ${data.disagree === 1 ? "says" : "say"} otherwise; ${data.disagree === 1 ? "it stays" : "they stay"} as ${data.disagree === 1 ? "it is" : "they are"}.`)
            this.agreeTarget.innerHTML = parts.join(" ")
            this.agreeTarget.classList.remove("hidden")
        }
    }

    money(cents) {
        const sign = cents < 0 ? "−" : (cents > 0 ? "+" : "")
        return sign + "$" + (Math.abs(cents) / 100).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })
    }

    // The category picker (shared/category_picker) for the direction chosen.
    activeCategory() {
        const income = this.checked("bank_rule[direction]") === "in"
        return this.picker(income ? this.categoryInTarget : this.categoryOutTarget)
    }

    picker(element) {
        return this.application.getControllerForElementAndIdentifier(element, "category-picker")
    }

    check(name, value) {
        const radio = this.element.querySelector(`[name="${name}"][value="${value}"]`)
        if (radio) radio.checked = true
    }

    checked(name) {
        const radio = this.element.querySelector(`[name="${name}"]:checked`)
        return radio ? radio.value : ""
    }
}
