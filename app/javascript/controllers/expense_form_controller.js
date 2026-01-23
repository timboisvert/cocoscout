import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "fixedMonthsFields",
    "fixedEventsFields",
    "dateRangeFields",
    "untilDateFields",
    "specificEventsFields"
  ]

  toggleSpreadFields(event) {
    const method = event.target.value

    // Hide all fields first
    this.hideAllFields()

    // Show the relevant fields
    switch (method) {
      case "fixed_months":
        if (this.hasFixedMonthsFieldsTarget) {
          this.fixedMonthsFieldsTarget.classList.remove("hidden")
        }
        break
      case "fixed_events":
        if (this.hasFixedEventsFieldsTarget) {
          this.fixedEventsFieldsTarget.classList.remove("hidden")
        }
        break
      case "date_range":
        if (this.hasDateRangeFieldsTarget) {
          this.dateRangeFieldsTarget.classList.remove("hidden")
        }
        break
      case "until_date":
        if (this.hasUntilDateFieldsTarget) {
          this.untilDateFieldsTarget.classList.remove("hidden")
        }
        break
      case "specific_events":
        if (this.hasSpecificEventsFieldsTarget) {
          this.specificEventsFieldsTarget.classList.remove("hidden")
        }
        break
    }
  }

  hideAllFields() {
    if (this.hasFixedMonthsFieldsTarget) {
      this.fixedMonthsFieldsTarget.classList.add("hidden")
    }
    if (this.hasFixedEventsFieldsTarget) {
      this.fixedEventsFieldsTarget.classList.add("hidden")
    }
    if (this.hasDateRangeFieldsTarget) {
      this.dateRangeFieldsTarget.classList.add("hidden")
    }
    if (this.hasUntilDateFieldsTarget) {
      this.untilDateFieldsTarget.classList.add("hidden")
    }
    if (this.hasSpecificEventsFieldsTarget) {
      this.specificEventsFieldsTarget.classList.add("hidden")
    }
  }
}
