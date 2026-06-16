import { Controller } from "@hotwired/stimulus"

// Unified document-sharing picker (Google-Docs style). One search box adds the
// production team, a talent pool, or a specific person to a single access list.
// Each added entry carries its own form inputs, so removing a row drops it from
// the submission. Already-added entries are filtered out of the search.
export default class extends Controller {
    static targets = ["search", "results", "rows", "empty", "teamTemplate", "poolTemplate", "personTemplate"]
    static values = { candidates: Array }

    addedKeys() {
        return new Set(
            Array.from(this.rowsTarget.querySelectorAll("[data-share-key]"))
                .map(el => el.dataset.shareKey)
        )
    }

    search() {
        const term = (this.searchTarget.value || "").trim().toLowerCase()
        const added = this.addedKeys()
        const matches = (this.candidatesValue || [])
            .filter(c => !added.has(c.key))
            .filter(c => !term || String(c.name || "").toLowerCase().includes(term))
            .slice(0, 40)

        if (matches.length === 0) {
            this.resultsTarget.innerHTML = `<div class="px-3 py-2 text-sm text-gray-400">No matches</div>`
        } else {
            this.resultsTarget.innerHTML = matches.map(c => {
                const avatar = c.kind === "person"
                    ? `<span class="w-7 h-7 rounded-full bg-gray-100 text-gray-600 flex items-center justify-center text-[10px] font-bold flex-shrink-0">${this.h(c.initials || "?")}</span>`
                    : `<span class="w-7 h-7 rounded-full bg-pink-50 text-pink-600 flex items-center justify-center flex-shrink-0"><svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M18 18.72a9.094 9.094 0 0 0 3.741-.479 3 3 0 0 0-4.682-2.72m.94 3.198.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0 1 12 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 0 1 6 18.719m12 0a5.971 5.971 0 0 0-.941-3.197m0 0A5.995 5.995 0 0 0 12 12.75a5.995 5.995 0 0 0-5.058 2.772m0 0a3 3 0 0 0-4.681 2.72 8.986 8.986 0 0 0 3.74.477m.94-3.197a5.971 5.971 0 0 0-.94 3.197M15 6.75a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm6 3a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm-13.5 0a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z"/></svg></span>`
                const sub = c.subtitle ? `<span class="text-xs text-gray-400 truncate">${this.h(c.subtitle)}</span>` : ""
                return `<button type="button" data-action="document-audience#add"
                        data-key="${this.h(c.key)}" data-kind="${this.h(c.kind)}" data-id="${this.h(c.id)}"
                        data-name="${this.h(c.name)}" data-initials="${this.h(c.initials || "")}"
                        class="w-full flex items-center gap-2.5 px-3 py-2 text-left hover:bg-pink-50 cursor-pointer">
                    ${avatar}
                    <span class="flex flex-col min-w-0"><span class="text-sm text-gray-800 truncate">${this.h(c.name)}</span>${sub}</span>
                </button>`
            }).join("")
        }
        this.resultsTarget.classList.remove("hidden")
    }

    add(event) {
        const { key, kind, id, name, initials } = event.currentTarget.dataset
        if (this.addedKeys().has(key)) return

        const template = kind === "team" ? this.teamTemplateTarget
            : kind === "talent_pool" ? this.poolTemplateTarget
            : this.personTemplateTarget
        const html = template.innerHTML
            .replaceAll("__ID__", this.h(id))
            .replaceAll("__NAME__", this.h(name))
            .replaceAll("__INIT__", this.h(initials || "?"))
        const wrap = document.createElement("div")
        wrap.innerHTML = html.trim()
        const row = wrap.firstElementChild
        if (row) this.rowsTarget.appendChild(row)

        this.searchTarget.value = ""
        this.resultsTarget.classList.add("hidden")
        this.refreshEmpty()
        this.searchTarget.focus()
    }

    remove(event) {
        event.currentTarget.closest("[data-share-key]")?.remove()
        this.refreshEmpty()
    }

    refreshEmpty() {
        if (!this.hasEmptyTarget) return
        const has = this.rowsTarget.querySelector("[data-share-key]")
        this.emptyTarget.classList.toggle("hidden", !!has)
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
