import { Controller } from "@hotwired/stimulus"

// Schedule form: top-level pattern picker drives which sub-fields show.
//
//   primary direct → resolved enum:
//     weekly                → weekly
//     biweekly              → biweekly
//     monthly_nth_weekdays  → monthly_nth_weekdays   ("multiple times per month")
//     monthly               → monthlyKind subselect (specific weekday / day-of-month)
//     custom_dates          → custom_dates           (no recurrence, just a list)
//
// Inputs that don't apply to the current choice get hidden. Custom
// dates uses its own controller (`mics-custom-dates`) for the list UI.
export default class extends Controller {
  static targets = [
    "primary", "monthlyKind", "hiddenPattern",
    "anchorBlock", "monthlyKindBlock",
    "nthBlock", "nthMultiBlock", "domBlock", "dowBlock",
    "customDatesBlock", "startTimeBlock"
  ]

  connect() { this.refresh() }

  refresh() {
    const primary = this.hasPrimaryTarget ? this.primaryTarget.value : "weekly"
    const monthlyKind = this.hasMonthlyKindTarget ? this.monthlyKindTarget.value : "monthly_nth_weekday"

    let resolved = primary
    if (primary === "monthly") resolved = monthlyKind
    if (this.hasHiddenPatternTarget) this.hiddenPatternTarget.value = resolved

    const isMonthlyAdvanced = primary === "monthly"
    const isCustom         = primary === "custom_dates"

    this.toggle(this.anchorBlockTarget,      primary === "biweekly")
    this.toggle(this.monthlyKindBlockTarget, isMonthlyAdvanced)
    this.toggle(this.nthBlockTarget,         isMonthlyAdvanced && monthlyKind === "monthly_nth_weekday")
    this.toggle(this.nthMultiBlockTarget,    isMonthlyAdvanced && monthlyKind === "monthly_nth_weekdays")
    this.toggle(this.domBlockTarget,         isMonthlyAdvanced && monthlyKind === "monthly_day_of_month")

    // "Multiple times per month" needs nth-week checkboxes too.
    if (primary === "monthly_nth_weekdays") this.toggle(this.nthMultiBlockTarget, true)

    // Day-of-week is needed for everything except day-of-month and custom dates.
    const showDow = !isCustom && !(isMonthlyAdvanced && monthlyKind === "monthly_day_of_month")
    this.toggle(this.dowBlockTarget, showDow)

    // Custom dates: hide the day-of-week + global start time, show the list.
    this.toggle(this.customDatesBlockTarget, isCustom)
    if (isCustom) this.toggle(this.dowBlockTarget, false)
    this.toggle(this.startTimeBlockTarget, !isCustom)
  }

  toggle(el, show) {
    if (el) el.classList.toggle("hidden", !show)
  }
}
