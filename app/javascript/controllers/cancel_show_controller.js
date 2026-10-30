import { Controller } from "@hotwired/stimulus"

// The cancel screen: which occurrences to cancel (only this one, this and
// future, or the whole series). Everything that depends on it follows the
// choice: the ticket buyers to refund (refundScope), the cast and staff who'll
// be notified next (peopleScope), and the confirm modal's words.
export default class extends Controller {
  static targets = [
    "scopeRadio",
    "scopeField",
    "cancelForm",
    "confirmMessage",
    "refundScope",
    "peopleScope"
  ]

  static values = {
    eventType: String,
    singleDate: String,
    occurrenceCount: Number,
    futureCount: Number
  }

  connect() {
    this.toggleScope()
  }

  toggleScope() {
    const selectedRadio = this.scopeRadioTargets.find(r => r.checked)
    const scope = selectedRadio ? selectedRadio.value : "this"

    if (this.hasScopeFieldTarget) {
      this.scopeFieldTarget.value = scope
    }

    // Each of these shows its count and its people for this scope only.
    ;[ ...this.refundScopeTargets, ...this.peopleScopeTargets ].forEach((block) => {
      block.classList.toggle("hidden", block.dataset.scope !== scope)
    })

    // Keep the in-page confirm modal's message in sync with the selected scope.
    if (this.hasConfirmMessageTarget) {
      let message
      if (scope === "all") {
        message = `Are you sure you want to cancel all ${this.occurrenceCountValue} occurrences in this series?`
      } else if (scope === "this_and_future") {
        message = `Are you sure you want to cancel this and ${this.futureCountValue - 1} future occurrences?`
      } else {
        message = `Are you sure you want to cancel this ${this.eventTypeValue.toLowerCase()} on ${this.singleDateValue}?`
      }
      this.confirmMessageTarget.textContent = message
    }
  }
}
