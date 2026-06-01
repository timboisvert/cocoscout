import { Controller } from "@hotwired/stimulus"

// Toggles the inputs on the producer Schedule form based on which
// recurrence pattern is selected:
//   weekly / biweekly        → show Day-of-week
//   monthly_nth_weekday      → show Nth-week + Day-of-week
//   monthly_day_of_month     → show Day-of-month (hide Day-of-week)
export default class extends Controller {
  static targets = ["pattern", "nthBlock", "domBlock", "dowBlock"]

  connect() { this.refresh() }

  refresh() {
    const v = this.hasPatternTarget ? this.patternTarget.value : "weekly"
    this.toggle(this.nthBlockTarget, v === "monthly_nth_weekday")
    this.toggle(this.domBlockTarget, v === "monthly_day_of_month")
    this.toggle(this.dowBlockTarget, v !== "monthly_day_of_month")
  }

  toggle(el, show) {
    if (el) el.classList.toggle("hidden", !show)
  }
}
