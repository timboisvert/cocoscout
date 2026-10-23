import { Controller } from "@hotwired/stimulus"

// The segment rule builder: each row shows the fields its kind of rule
// needs, rows come and go, and the count on the side follows the rules as
// they change (Manage::SegmentsController#count).
export default class extends Controller {
    static targets = ["form", "rows", "row", "template", "count", "sample"]
    static values = { countUrl: String }

    connect() {
        this.next = Date.now()
        this.rowTargets.forEach(row => this.showFields(row))
        this.refresh()
    }

    changed(event) {
        const row = event.target.closest("[data-segment-builder-target='row']")
        if (row) this.showFields(row)
        clearTimeout(this.timer)
        this.timer = setTimeout(() => this.refresh(), 250)
    }

    add() {
        const html = this.templateTarget.innerHTML.replaceAll("INDEX", String(this.next++))
        this.rowsTarget.insertAdjacentHTML("beforeend", html)
        this.showFields(this.rowTargets[this.rowTargets.length - 1])
        this.refresh()
    }

    remove(event) {
        if (this.rowTargets.length <= 1) return
        event.target.closest("[data-segment-builder-target='row']").remove()
        this.refresh()
    }

    // style, not a class: these spans are display: contents
    showFields(row) {
        const type = row.querySelector("[data-role='type']").value
        row.querySelectorAll("[data-for]").forEach(span => {
            const on = span.dataset.for.split(" ").includes(type)
            span.style.display = on ? "contents" : "none"
            span.querySelectorAll("input, select").forEach(field => { field.disabled = !on })
        })
    }

    async refresh() {
        const params = new URLSearchParams(new FormData(this.formTarget))
        params.delete("authenticity_token")
        params.delete("_method")
        const response = await fetch(`${this.countUrlValue}?${params.toString()}`, { headers: { Accept: "application/json" } })
        if (!response.ok) return
        const data = await response.json()
        this.countTarget.textContent = data.count.toLocaleString()
        this.sampleTarget.innerHTML = ""
        if (data.sample.length === 0) {
            const p = document.createElement("p")
            p.className = "text-gray-500"
            p.textContent = "Nobody matches yet."
            this.sampleTarget.appendChild(p)
        }
        data.sample.forEach(person => {
            const row = document.createElement("div")
            row.className = "min-w-0"
            const name = document.createElement("div")
            name.className = "font-semibold text-gray-900 truncate"
            name.textContent = person.name
            const email = document.createElement("div")
            email.className = "text-xs text-gray-500 truncate"
            email.textContent = person.email
            row.append(name, email)
            this.sampleTarget.appendChild(row)
        })
    }
}
