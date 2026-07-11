import { Controller } from "@hotwired/stimulus"

// Keeps the department <select> in sync with the departments managed in the
// modal's Turbo-frame. The select lives in the surrounding form (outside this
// controller), so we reach it by id. Called when the modal closes: rebuilds the
// options from the frame's current list while preserving the current selection.
export default class extends Controller {
    static targets = ["frame"]
    static values = { select: String }

    sync() {
        const select = document.getElementById(this.selectValue)
        if (!select || !this.hasFrameTarget) return

        const names = Array.from(this.frameTarget.querySelectorAll("[data-dept-name]"))
            .map(el => el.dataset.deptName)
        const current = select.value

        let html = `<option value="">No department</option>`
        names.forEach(n => {
            html += `<option value="${this.escapeAttr(n)}"${n === current ? " selected" : ""}>${this.escapeText(n)}</option>`
        })
        if (current && !names.includes(current)) {
            html += `<option value="${this.escapeAttr(current)}" selected>${this.escapeText(current)}</option>`
        }
        select.innerHTML = html
        select.value = current
    }

    escapeText(str) {
        const d = document.createElement("div")
        d.textContent = String(str == null ? "" : str)
        return d.innerHTML
    }

    escapeAttr(str) {
        return this.escapeText(str).replace(/"/g, "&quot;")
    }
}
