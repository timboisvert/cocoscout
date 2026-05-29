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
