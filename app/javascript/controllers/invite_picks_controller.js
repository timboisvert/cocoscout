import { Controller } from "@hotwired/stimulus"

// Who to invite to a vacancy (V1.1 plan §5): picks from the shared People
// Picker ("vacancy-picker") become chips and member_ids[] fields on the
// invitation form; "Add all" takes a list the page wrote out.
export default class extends Controller {
    static targets = ["chips", "fields", "count"]

    connect() {
        this.picked = new Set()
    }

    picked(event) {
        const pick = event.detail
        if (pick.picker !== "vacancy-picker" || !pick.type) return
        this.add(`${pick.type}_${pick.id}`, pick.name, pick.initials, pick.headshotUrl || "")
    }

    addAll(event) {
        let members = []
        try { members = JSON.parse(event.currentTarget.dataset.members || "[]") } catch { return }
        members.forEach(m => this.add(m.key, m.name, m.initials, m.headshotUrl || ""))
    }

    add(key, name, initials, headshot) {
        if (this.picked.has(key)) return
        this.picked.add(key)
        const chip = document.createElement("span")
        chip.className = "inline-flex items-center gap-2 pl-1.5 pr-2 py-1 bg-pink-50 border border-pink-200 rounded-lg text-sm"
        chip.dataset.key = key
        chip.innerHTML = `
      ${headshot ? `<img src="${this.escape(headshot)}" alt="" class="w-6 h-6 rounded-lg object-cover">` : `<span class="w-6 h-6 rounded-lg bg-pink-100 text-pink-700 text-[10px] font-bold flex items-center justify-center">${this.escape(initials || "")}</span>`}
      <span class="text-gray-900 font-medium">${this.escape(name)}</span>
      <button type="button" class="w-6 h-6 inline-flex items-center justify-center rounded-full text-gray-400 hover:text-gray-700 cursor-pointer" aria-label="Remove ${this.escape(name)}" data-action="click->invite-picks#remove" data-key="${this.escape(key)}">
        <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12"/></svg>
      </button>`
        this.chipsTarget.appendChild(chip)
        const field = document.createElement("input")
        field.type = "hidden"
        field.name = "member_ids[]"
        field.value = key
        field.dataset.key = key
        this.fieldsTarget.appendChild(field)
        this.refresh()
    }

    remove(event) {
        const key = event.currentTarget.dataset.key
        this.picked.delete(key)
        this.chipsTarget.querySelector(`[data-key="${CSS.escape(key)}"]`)?.remove()
        this.fieldsTarget.querySelector(`input[data-key="${CSS.escape(key)}"]`)?.remove()
        this.refresh()
    }

    refresh() {
        if (!this.hasCountTarget) return
        const n = this.picked.size
        this.countTarget.textContent = n === 0 ? "Nobody chosen yet" : `${n} chosen`
    }

    escape(text) {
        const div = document.createElement("div")
        div.textContent = String(text)
        return div.innerHTML
    }
}
