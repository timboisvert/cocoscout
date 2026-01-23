import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "fixedMonthsFields",
    "fixedEventsFields",
    "dateRangeFields",
    "untilDateFields",
    "specificEventsFields"
  ]

  connect() {
    // Disable inputs in hidden sections on initial load
    this.disableHiddenInputs()
  }

  toggleSpreadFields(event) {
    const method = event.target.value

    // Hide all fields first and disable their inputs
    this.hideAllFields()

    // Show the relevant fields and enable their inputs
    switch (method) {
      case "fixed_months":
        if (this.hasFixedMonthsFieldsTarget) {
          this.showAndEnable(this.fixedMonthsFieldsTarget)
        }
        break
      case "fixed_events":
        if (this.hasFixedEventsFieldsTarget) {
          this.showAndEnable(this.fixedEventsFieldsTarget)
        }
        break
      case "date_range":
        if (this.hasDateRangeFieldsTarget) {
          this.showAndEnable(this.dateRangeFieldsTarget)
        }
        break
      case "until_date":
        if (this.hasUntilDateFieldsTarget) {
          this.showAndEnable(this.untilDateFieldsTarget)
        }
        break
      case "specific_events":
        if (this.hasSpecificEventsFieldsTarget) {
          this.showAndEnable(this.specificEventsFieldsTarget)
        }
        break
    }
  }

  showAndEnable(target) {
    target.classList.remove("hidden")
    target.querySelectorAll("input, select, textarea").forEach(input => {
      input.disabled = false
    })
  }

  hideAndDisable(target) {
    target.classList.add("hidden")
    target.querySelectorAll("input, select, textarea").forEach(input => {
      input.disabled = true
    })
  }

  hideAllFields() {
    if (this.hasFixedMonthsFieldsTarget) {
      this.hideAndDisable(this.fixedMonthsFieldsTarget)
    }
    if (this.hasFixedEventsFieldsTarget) {
      this.hideAndDisable(this.fixedEventsFieldsTarget)
    }
    if (this.hasDateRangeFieldsTarget) {
      this.hideAndDisable(this.dateRangeFieldsTarget)
    }
    if (this.hasUntilDateFieldsTarget) {
      this.hideAndDisable(this.untilDateFieldsTarget)
    }
    if (this.hasSpecificEventsFieldsTarget) {
      this.hideAndDisable(this.specificEventsFieldsTarget)
    }
  }

  disableHiddenInputs() {
    // Disable inputs in any sections that are currently hidden
    const allTargets = [
      this.hasFixedMonthsFieldsTarget ? this.fixedMonthsFieldsTarget : null,
      this.hasFixedEventsFieldsTarget ? this.fixedEventsFieldsTarget : null,
      this.hasDateRangeFieldsTarget ? this.dateRangeFieldsTarget : null,
      this.hasUntilDateFieldsTarget ? this.untilDateFieldsTarget : null,
      this.hasSpecificEventsFieldsTarget ? this.specificEventsFieldsTarget : null
    ].filter(Boolean)

    allTargets.forEach(target => {
      if (target.classList.contains("hidden")) {
        target.querySelectorAll("input, select, textarea").forEach(input => {
          input.disabled = true
        })
      }
    })
  }
}
