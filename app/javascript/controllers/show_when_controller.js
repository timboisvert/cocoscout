import { Controller } from "@hotwired/stimulus"

// Questions that only show once the answer above them is yes (Tim,
// 2026-11-21, the comp rules: "we don't even need to show them the toggle
// for whether they should be allowed to request more"). Inside the
// controller's element, any element with
//   data-show-when="id id"      shows only while every named checkbox or
//                               radio is checked
//   data-show-when-any="id id"  ...and at least one of these is
//   data-show-unless="id"       shows only while that one is NOT checked
// Hidden questions keep their values, so turning the answer back on finds
// them as they were.
export default class extends Controller {
    connect() {
        this.update = this.update.bind(this)
        this.element.addEventListener("change", this.update)
        this.update()
    }

    disconnect() {
        this.element.removeEventListener("change", this.update)
    }

    update() {
        const checked = (id) => document.getElementById(id)?.checked === true
        const ids = (el, name) => (el.dataset[name] || "").split(/\s+/).filter(Boolean)

        this.element.querySelectorAll("[data-show-when], [data-show-when-any], [data-show-unless]").forEach((el) => {
            const all = ids(el, "showWhen").every(checked)
            const anyIds = ids(el, "showWhenAny")
            const any = anyIds.length === 0 || anyIds.some(checked)
            const unless = ids(el, "showUnless").some(checked)
            el.hidden = !(all && any && !unless)
        })
    }
}
