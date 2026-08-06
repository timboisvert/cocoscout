import { Controller } from "@hotwired/stimulus"

// Per-day view toggle on the staffing schedule. Three modes:
//   - cards         (default): the per-role columns of shift cards
//   - gantt-roles:  rows = roles, time axis = horizontal
//   - gantt-people: rows = people assigned that day, time axis = horizontal
//
// State is purely client-side — each day row toggles independently.
export default class extends Controller {
    static targets = ["cards", "ganttRoles", "ganttPeople", "toggle"]
    static values = { mode: { type: String, default: "cards" } }

    // Every scheduling action morphs this page in place, and a morph patches the
    // DOM back towards what the server rendered. The chosen view is client-side
    // state the server knows nothing about, so it would snap back to cards on
    // every assign. Two hooks keep it: refuse the morph of the attribute holding
    // the mode, then re-apply the visibility classes the morph just reset.
    connect() {
        this.keepMode = this.keepMode.bind(this)
        this.reapplyMode = this.reapplyMode.bind(this)
        this.element.addEventListener("turbo:before-morph-attribute", this.keepMode)
        document.addEventListener("turbo:morph", this.reapplyMode)
    }

    disconnect() {
        this.element.removeEventListener("turbo:before-morph-attribute", this.keepMode)
        document.removeEventListener("turbo:morph", this.reapplyMode)
    }

    keepMode(event) {
        if (event.detail?.attributeName === "data-day-view-mode-value") event.preventDefault()
    }

    reapplyMode() {
        this.modeValueChanged()
    }

    setMode(event) {
        if (event) event.preventDefault()
        this.modeValue = event.currentTarget.dataset.mode
    }

    modeValueChanged() {
        const mode = this.modeValue
        // Multiple elements can share each target name (e.g. the cards scroller +
        // the day's show list below it) — iterate to toggle them together.
        this.cardsTargets.forEach(el       => el.classList.toggle("hidden", mode !== "cards"))
        this.ganttRolesTargets.forEach(el  => el.classList.toggle("hidden", mode !== "gantt-roles"))
        this.ganttPeopleTargets.forEach(el => el.classList.toggle("hidden", mode !== "gantt-people"))

        this.toggleTargets.forEach(btn => {
            const active = btn.dataset.mode === mode
            btn.classList.toggle("bg-pink-100", active)
            btn.classList.toggle("text-pink-700", active)
            btn.classList.toggle("text-gray-400", !active)
        })
    }
}
