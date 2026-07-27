import { Controller } from "@hotwired/stimulus"

// Live curated-vs-open toggling, on both the audition wizard's format step and
// the settings page. Reacts to the signup_mode radios:
//   - curatedOptions targets show only for "curated" (format toggles, review team)
//   - openOptions targets show only for "open" (e.g. allow-slot-changes)
//   - modeCard targets get the pink selected-card highlight for whichever radio
//     they contain is checked
// Defaults to whatever the server rendered, so it still works without JS.
export default class extends Controller {
    static targets = ["curatedOptions", "openOptions", "modeCard"]

    connect() {
        this.update()
    }

    update() {
        const selected = this.element.querySelector('input[name*="signup_mode"]:checked')
        const open = selected?.value === "open"

        this.curatedOptionsTargets.forEach((el) => el.classList.toggle("hidden", open))
        this.openOptionsTargets.forEach((el) => el.classList.toggle("hidden", !open))

        this.modeCardTargets.forEach((card) => {
            const on = !!card.querySelector('input[name*="signup_mode"]')?.checked
            card.classList.toggle("border-pink-400", on)
            card.classList.toggle("bg-pink-50", on)
            card.classList.toggle("border-gray-200", !on)
        })
    }
}
