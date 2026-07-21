import { Controller } from "@hotwired/stimulus"

// Sums the per-instructor amount inputs in the "Pay instructors" modal and
// shows a running subtotal.
export default class extends Controller {
  static targets = ["amount", "subtotal"]

  connect() {
    this.recalculate()
  }

  recalculate() {
    const total = this.amountTargets.reduce((sum, input) => {
      const value = parseFloat(input.value)
      return sum + (isNaN(value) ? 0 : value)
    }, 0)

    this.subtotalTarget.textContent = total.toLocaleString("en-US", {
      style: "currency",
      currency: "USD"
    })
  }
}
