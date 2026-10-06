import { Controller } from "@hotwired/stimulus"
import { orderTotalCents, money } from "controllers/lib/ticket_pricing"

// A pass page's stepper: how many passes, and their exact all-in total
// (TicketPricing's math: our fee for each show, processing once), so the
// total shown is the total checkout charges.
export default class extends Controller {
  static targets = ["quantity", "count", "button", "summary", "total"]
  static values = { base: Number, paid: Number, feeMode: String, platformFee: Number, perMille: Number, fixed: Number, max: Number }

  connect() {
    this.render()
  }

  increment() {
    this.set(this.current() + 1)
  }

  decrement() {
    this.set(this.current() - 1)
  }

  current() {
    return parseInt(this.quantityTarget.value, 10) || 0
  }

  set(count) {
    const max = this.maxValue > 0 ? this.maxValue : 20
    this.quantityTarget.value = Math.min(Math.max(count, 0), max)
    this.render()
  }

  render() {
    const count = this.current()
    this.countTarget.textContent = count
    const total = orderTotalCents({
      base: this.baseValue * count, paid: this.paidValue * count, feeMode: this.feeModeValue,
      platformFee: this.platformFeeValue, perMille: this.perMilleValue, fixed: this.fixedValue
    })
    this.buttonTarget.disabled = count === 0
    this.summaryTarget.textContent = count === 0 ? "Pick how many" : `${count} ${count === 1 ? "pass" : "passes"}`
    this.totalTarget.textContent = count === 0 ? "" : money(total)
  }
}
