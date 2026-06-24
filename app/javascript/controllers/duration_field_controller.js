import { Controller } from "@hotwired/stimulus"

// Combines an hours <select> and a minutes <select> (15-min increments)
// into a single hidden field.
//
//   unit: "minutes" (default) -> hidden field holds total minutes (e.g. 150)
//   unit: "hours"             -> hidden field holds decimal hours   (e.g. 2.5)
//
// Usage: see app/views/shared/_duration_field.html.erb
export default class extends Controller {
  static targets = ["hours", "minutes", "total"]
  static values = { unit: { type: String, default: "minutes" } }

  connect() {
    this.sync()
  }

  sync() {
    const hours = parseInt(this.hoursTarget.value || "0", 10)
    const minutes = parseInt(this.minutesTarget.value || "0", 10)

    if (this.unitValue === "hours") {
      const decimal = Math.round((hours + minutes / 60) * 100) / 100
      this.totalTarget.value = String(decimal)
    } else {
      this.totalTarget.value = hours * 60 + minutes
    }

    this.totalTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
