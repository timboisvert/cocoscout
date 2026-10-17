import { Controller } from "@hotwired/stimulus"

// A switch that greys out part of a form without disabling it: off, the
// dimmed parts fade and ignore clicks, but their values still travel with
// the form, so switching back on finds them as they were. (The comp rules:
// comps off keeps the per-date limit for when they're on again.) For a part
// whose values must NOT be sent when off, use fieldset-toggle instead.
export default class extends Controller {
    static targets = ["switch", "dimmed"]

    connect() {
        this.toggle()
    }

    toggle() {
        const on = this.switchTarget.checked
        this.dimmedTargets.forEach((el) => {
            el.classList.toggle("opacity-50", !on)
            el.classList.toggle("pointer-events-none", !on)
            el.setAttribute("aria-disabled", on ? "false" : "true")
        })
    }
}
