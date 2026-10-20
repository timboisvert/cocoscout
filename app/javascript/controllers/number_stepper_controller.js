import { Controller } from "@hotwired/stimulus"

// A − / + pair beside a number box (V1.1 plan §5, "Number row + stepper").
// The box stays the field: each tap changes its value by `step` and fires
// its input event, so whatever listens to typing hears the tap too.
export default class extends Controller {
    static targets = ["input"]
    static values = { step: { type: Number, default: 1 }, min: { type: Number, default: 0 } }

    up() { this.bump(this.stepValue) }

    down() { this.bump(-this.stepValue) }

    bump(delta) {
        const input = this.inputTarget
        const current = parseFloat(input.value) || 0
        const next = Math.max(this.minValue, Math.round((current + delta) * 100) / 100)
        input.value = next === 0 && !input.value ? "" : String(next)
        if (next === 0 && input.value === "") return
        input.dispatchEvent(new Event("input", { bubbles: true }))
        input.dispatchEvent(new Event("change", { bubbles: true }))
    }
}
