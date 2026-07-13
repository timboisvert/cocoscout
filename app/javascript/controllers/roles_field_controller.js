import { Controller } from "@hotwired/stimulus"

// Keeps the role-assignment checkboxes in sync with the roles managed in the
// modal's Turbo-frame. The checkbox grid lives in the surrounding form (outside
// this controller), so we reach it by id. Called when the modal closes:
// rebuilds the grid from the frame's current roles, preserving which are checked.
export default class extends Controller {
    static targets = ["frame"]
    static values = { list: String, empty: String }

    sync() {
        const list = document.getElementById(this.listValue)
        if (!list || !this.hasFrameTarget) return

        const rows = this.frameTarget.querySelectorAll("[data-role-id]")
        // Preserve which roles are checked and any rates already typed in.
        const checked = new Set(
            Array.from(list.querySelectorAll('input[data-role-checkbox]:checked')).map(i => i.value)
        )
        const rates = {}
        list.querySelectorAll("[data-role-row]").forEach(row => {
            const id = row.dataset.roleId
            const rate = row.querySelector("[data-role-rate]")
            if (id && rate && rate.value) rates[id] = rate.value
        })
        const placeholder = list.dataset.ratePlaceholder || "0.00"

        let html = ""
        rows.forEach(r => {
            const id = r.dataset.roleId
            const name = this.escape(r.dataset.roleName)
            const isChecked = checked.has(id) ? "checked" : ""
            const rateVal = rates[id] ? this.escape(rates[id]) : ""
            html += `<label class="flex items-center gap-3 p-3 rounded-lg border border-gray-200 cursor-pointer" data-role-row data-role-id="${id}">` +
                `<input type="checkbox" name="house_role_ids[]" value="${id}" ${isChecked} data-role-checkbox class="h-4 w-4 rounded border-gray-300 accent-pink-500">` +
                `<span class="flex-1 text-sm font-medium text-gray-800">${name}</span>` +
                `<div class="relative w-28 flex-shrink-0">` +
                `<span class="absolute left-2 top-1/2 -translate-y-1/2 text-gray-400 text-sm">$</span>` +
                `<input type="text" inputmode="decimal" name="role_rates[${id}]" value="${rateVal}" placeholder="${this.escape(placeholder)}" data-role-rate class="w-full pl-5 pr-8 py-1.5 border border-gray-200 rounded text-right text-sm focus:outline-none focus:ring-1 focus:ring-pink-300">` +
                `<span class="absolute right-2 top-1/2 -translate-y-1/2 text-gray-400 text-xs">/hr</span>` +
                `</div>` +
                `</label>`
        })
        list.innerHTML = html

        if (this.hasEmptyValue) {
            const emptyEl = document.getElementById(this.emptyValue)
            if (emptyEl) emptyEl.classList.toggle("hidden", rows.length > 0)
        }
    }

    escape(str) {
        const d = document.createElement("div")
        d.textContent = String(str == null ? "" : str)
        return d.innerHTML
    }
}
