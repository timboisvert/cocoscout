import { Controller } from "@hotwired/stimulus"

// The Change-the-room screen. Two jobs: set a whole venue's dates to one room
// in a single move, and arm the "change it anyway" submit once we've warned
// about a clash.
export default class extends Controller {
    static targets = ["select", "force"]

    // Bulk control at the top of a venue group. "__none__" is the resting
    // label, not a room — picking it leaves every row as the manager set it.
    applyAll(event) {
        const value = event.currentTarget.value
        if (value === "__none__") return

        const locationId = event.currentTarget.dataset.locationId
        this.selectTargets
            .filter((select) => select.dataset.locationId === locationId)
            .forEach((select) => {
                select.value = value
            })
    }

    force() {
        if (this.hasForceTarget) this.forceTarget.value = "1"
    }
}
