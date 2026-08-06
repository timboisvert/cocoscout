import { Controller } from "@hotwired/stimulus"

// One row per date on the Change-dates screen. Only reveals the new-date field
// when that row is actually being moved, so a stray datetime can't ride along
// with a row the manager left alone.
export default class extends Controller {
    static targets = ["moveFields"]

    modeChanged(event) {
        if (!this.hasMoveFieldsTarget) return
        this.moveFieldsTarget.classList.toggle("hidden", event.currentTarget.value !== "move")
    }
}
