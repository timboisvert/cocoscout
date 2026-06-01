import { Controller } from "@hotwired/stimulus"

// Schedule form: a two-step picker.
//
//   primary:  weekly | biweekly | monthly
//   if monthly → monthlyKind: monthly_nth_weekday | monthly_day_of_month
//
// We resolve to the persisted enum value and write it into the hidden
// `mic[recurrence_pattern]` field. Inputs that don't apply to the
// current choice get hidden.
export default class extends Controller {
  static targets = [
    "primary", "monthlyKind", "hiddenPattern",
    "anchorBlock", "monthlyKindBlock", "nthBlock", "domBlock", "dowBlock"
  ]

  connect() { this.refresh() }

  refresh() {
    const primary = this.hasPrimaryTarget ? this.primaryTarget.value : "weekly"
    const monthlyKind = this.hasMonthlyKindTarget ? this.monthlyKindTarget.value : "monthly_nth_weekday"

    let resolved = primary
    if (primary === "monthly") resolved = monthlyKind
    if (this.hasHiddenPatternTarget) this.hiddenPatternTarget.value = resolved

    this.toggle(this.anchorBlockTarget,       primary === "biweekly")
    this.toggle(this.monthlyKindBlockTarget,  primary === "monthly")
    this.toggle(this.nthBlockTarget,          primary === "monthly" && monthlyKind === "monthly_nth_weekday")
    this.toggle(this.domBlockTarget,          primary === "monthly" && monthlyKind === "monthly_day_of_month")
    this.toggle(this.dowBlockTarget,          !(primary === "monthly" && monthlyKind === "monthly_day_of_month"))
  }

  toggle(el, show) {
    if (el) el.classList.toggle("hidden", !show)
  }
}
