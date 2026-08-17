import { Controller } from "@hotwired/stimulus"

// Shows the selected payout scheme's rules summary under the picker, so the
// choice reads as "Per Act — $75 for act 1, $50 for act 2…" not just a name.
export default class extends Controller {
  static targets = ["select", "summary"]

  connect() {
    this.describe()
  }

  describe() {
    if (!this.hasSelectTarget || !this.hasSummaryTarget) return
    const option = this.selectTarget.selectedOptions[0]
    this.summaryTarget.textContent = option ? (option.dataset.summary || "") : ""
  }
}
