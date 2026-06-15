import { Controller } from "@hotwired/stimulus"

// "Specific people" picker for document sharing. Search a candidate list, click
// to add a person as a chip (with a hidden person_ids[] input), or remove one.
export default class extends Controller {
    static targets = ["search", "results", "chips", "rowTemplate"]
    static values = { candidates: Array }

    selectedIds() {
        return Array.from(this.chipsTarget.querySelectorAll("[data-person-id]"))
            .map(el => String(el.dataset.personId))
    }

    search() {
        const term = (this.searchTarget.value || "").trim().toLowerCase()
        const chosen = new Set(this.selectedIds())
        const matches = (this.candidatesValue || [])
            .filter(c => !chosen.has(String(c.id)))
            .filter(c => !term || String(c.name || "").toLowerCase().includes(term))
            .slice(0, 30)

        if (matches.length === 0) {
            this.resultsTarget.innerHTML = `<div class="px-3 py-2 text-sm text-gray-400">No matches</div>`
        } else {
            this.resultsTarget.innerHTML = matches.map(c => `
                <button type="button" data-action="document-audience#add"
                        data-id="${c.id}" data-name="${this.h(c.name)}"
                        class="w-full flex items-center gap-2 px-3 py-2 text-left text-sm hover:bg-pink-50 cursor-pointer">
                    <span class="w-6 h-6 rounded bg-gray-100 text-gray-600 flex items-center justify-center text-[10px] font-bold flex-shrink-0">${this.h(c.initials || "?")}</span>
                    <span class="truncate">${this.h(c.name)}</span>
                </button>`).join("")
        }
        this.resultsTarget.classList.remove("hidden")
    }

    add(event) {
        const { id, name } = event.currentTarget.dataset
        if (this.selectedIds().includes(String(id))) return
        // Build a row from the server-rendered <template> (a person-share row
        // with a read/write select), substituting this person's id + name.
        const html = (this.hasRowTemplateTarget ? this.rowTemplateTarget.innerHTML : "")
            .replaceAll("__ID__", this.h(id))
            .replaceAll("__NAME__", this.h(name))
        const wrap = document.createElement("div")
        wrap.innerHTML = html.trim()
        const row = wrap.firstElementChild
        if (row) this.chipsTarget.appendChild(row)
        this.searchTarget.value = ""
        this.resultsTarget.classList.add("hidden")
        this.searchTarget.focus()
    }

    remove(event) {
        event.currentTarget.closest("[data-person-id]")?.remove()
    }

    // Hide the dropdown when clicking elsewhere.
    clickOutside(event) {
        if (!this.element.contains(event.target)) this.resultsTarget.classList.add("hidden")
    }

    connect() { this._outside = this.clickOutside.bind(this); document.addEventListener("click", this._outside) }
    disconnect() { document.removeEventListener("click", this._outside) }

    h(s) {
        if (s == null) return ""
        const d = document.createElement("div")
        d.textContent = String(s)
        return d.innerHTML
    }
}
