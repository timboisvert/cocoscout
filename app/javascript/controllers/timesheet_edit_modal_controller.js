import { Controller } from "@hotwired/stimulus"

// Drives the timesheet edit / re-approve modal on the approved-hours page.
// The modal content lives inside a top-level turbo frame ("timesheet_edit_modal");
// loading a URL into that frame shows the overlay, emptying it hides the overlay.
//
// Two dismissal behaviors:
//   close  — used while editing (nothing changed yet): just empty the frame.
//   reload — used after a save (the entry was kicked back to review): refresh the
//            list so it reflects the new state, whichever way the manager exits.
export default class extends Controller {
  static targets = ["started", "ended", "role", "payBreakdown", "payTotal"]

  connect() {
    if (this.hasPayTotalTarget) this.recalc()
  }

  // Live pay preview: hours between the two clock fields, priced at the
  // selected role's rate (carried on each option as data attributes).
  // Flat roles ignore hours — that's the point of a flat rate.
  recalc() {
    if (!this.hasPayTotalTarget) return

    const s = this.hasStartedTarget ? Date.parse(this.startedTarget.value) : NaN
    const e = this.hasEndedTarget ? Date.parse(this.endedTarget.value) : NaN
    let hours = 0
    if (!isNaN(s) && !isNaN(e) && e > s) hours = Math.round(((e - s) / 3600000) * 100) / 100

    const opt = this.hasRoleTarget ? this.roleTarget.selectedOptions[0] : null
    const rateCents = parseInt(opt?.dataset.rateCents || "0", 10)
    const flat = opt?.dataset.rateType === "flat"
    const rateLabel = opt?.dataset.rateLabel

    if (!rateCents || !rateLabel) {
      this.payBreakdownTarget.textContent = `${hours} hrs — no rate set for this role, so `
      this.payTotalTarget.textContent = "$0.00"
      return
    }

    const totalCents = flat ? rateCents : Math.round(hours * rateCents)
    const money = (cents) => (cents / 100).toLocaleString("en-US", { style: "currency", currency: "USD" })
    this.payBreakdownTarget.textContent = flat
      ? `${rateLabel} (flat) → `
      : `${hours} hrs × ${rateLabel} → `
    this.payTotalTarget.textContent = money(totalCents)
  }

  frame() {
    return document.getElementById("timesheet_edit_modal")
  }

  close() {
    const frame = this.frame()
    if (frame) frame.innerHTML = ""
  }

  closeOnBackdrop(event) {
    if (event.target === this.element) this.close()
  }

  reload() {
    Turbo.visit(window.location.href, { action: "replace" })
  }

  reloadOnBackdrop(event) {
    if (event.target === this.element) this.reload()
  }

  stopPropagation(event) {
    event.stopPropagation()
  }
}
