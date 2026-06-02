import { Controller } from "@hotwired/stimulus"

// Schedule form: a two-step picker.
//
//   primary:  weekly | biweekly | monthly
//   if monthly → monthlyKind:
//     monthly_nth_weekday   — one Nth weekday per month (single select)
//     monthly_nth_weekdays  — multiple Nth weekdays per month (checkboxes)
//     monthly_day_of_month  — a specific day-of-month integer
//
// We resolve to the persisted enum value and write it into the hidden
// `mic[recurrence_pattern]` field. Inputs that don't apply to the
// current choice get hidden.
export default class extends Controller {
  static targets = [
    "primary", "monthlyKind", "hiddenPattern",
    "anchorBlock", "monthlyKindBlock",
    "nthBlock", "nthMultiBlock", "domBlock", "dowBlock"
  ]

  connect() { this.refresh() }

  refresh() {
    const primary = this.hasPrimaryTarget ? this.primaryTarget.value : "weekly"
    const monthlyKind = this.hasMonthlyKindTarget ? this.monthlyKindTarget.value : "monthly_nth_weekday"

    let resolved = primary
    if (primary === "monthly") resolved = monthlyKind
    if (this.hasHiddenPatternTarget) this.hiddenPatternTarget.value = resolved

    const isMonthly = primary === "monthly"
    this.toggle(this.anchorBlockTarget,      primary === "biweekly")
    this.toggle(this.monthlyKindBlockTarget, isMonthly)
    this.toggle(this.nthBlockTarget,         isMonthly && monthlyKind === "monthly_nth_weekday")
    this.toggle(this.nthMultiBlockTarget,    isMonthly && monthlyKind === "monthly_nth_weekdays")
    this.toggle(this.domBlockTarget,         isMonthly && monthlyKind === "monthly_day_of_month")
    this.toggle(this.dowBlockTarget,         !(isMonthly && monthlyKind === "monthly_day_of_month"))
  }

  toggle(el, show) {
    if (el) el.classList.toggle("hidden", !show)
  }
}
