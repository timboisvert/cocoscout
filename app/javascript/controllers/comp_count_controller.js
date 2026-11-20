import { Controller } from "@hotwired/stimulus"

// A comp request's number and what it makes (CompRequest): "3 now + 4
// requested = 7 if approved", kept in step as the stepper moves.
export default class extends Controller {
    static targets = ["input", "added", "total"]
    static values = { now: Number }

    connect() {
        this.update()
    }

    update() {
        const added = Math.max(parseInt(this.inputTarget.value, 10) || 0, 0)
        this.addedTargets.forEach((el) => { el.textContent = String(added) })
        this.totalTargets.forEach((el) => { el.textContent = String(this.nowValue + added) })
    }
}
