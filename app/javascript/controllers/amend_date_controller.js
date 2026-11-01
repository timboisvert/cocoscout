import { Controller } from "@hotwired/stimulus"

// One row per date on the Change-dates screen. Only reveals the new-date
// fields when that row is actually being moved, and only then lets them
// submit: the form is a GET, and a contract's worth of rows each sending
// four times would outgrow the address (Puma stops at 10KB of query and
// answers an empty 400, which Turbo shows as nothing happening). A kept or
// removed row sends its action alone.
export default class extends Controller {
    static targets = ["moveFields"]

    modeChanged(event) {
        if (!this.hasMoveFieldsTarget) return
        const moving = event.currentTarget.value === "move"
        this.moveFieldsTarget.classList.toggle("hidden", !moving)
        this.moveFieldsTarget.querySelectorAll("input, select").forEach((field) => { field.disabled = !moving })
    }
}
