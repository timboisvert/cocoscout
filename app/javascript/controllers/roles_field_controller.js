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
        const checked = new Set(
            Array.from(list.querySelectorAll('input[type="checkbox"]:checked')).map(i => i.value)
        )

        let html = ""
        rows.forEach(r => {
            const id = r.dataset.roleId
            const name = r.dataset.roleName
            const isChecked = checked.has(id) ? "checked" : ""
            html += `<label class="relative cursor-pointer">` +
                `<input type="checkbox" name="house_role_ids[]" value="${id}" ${isChecked} class="sr-only peer">` +
                `<span class="block text-center text-sm font-medium px-2 py-3 rounded-lg border bg-white text-gray-700 border-gray-200 hover:border-pink-400 peer-checked:bg-pink-500 peer-checked:text-white peer-checked:border-pink-500 transition-colors">${this.escape(name)}</span>` +
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
