import { Controller } from "@hotwired/stimulus"

// The 6-digit code field (shared/auth/_code_field): one real, see-through
// input lies over six drawn boxes. Every change to the input is mirrored into
// the boxes, and the box the next digit goes in gets the pink ring while the
// input has focus. One input means a paste, the keyboard's "From Mail" code,
// and autofill all work in one go.
export default class extends Controller {
  static targets = ["input", "cell"]

  connect() {
    this.draw()
  }

  draw() {
    const digits = this.inputTarget.value.replace(/\D/g, "").slice(0, this.cellTargets.length)
    if (digits !== this.inputTarget.value) this.inputTarget.value = digits

    const focused = document.activeElement === this.inputTarget
    const next = Math.min(digits.length, this.cellTargets.length - 1)
    this.cellTargets.forEach((cell, i) => {
      cell.textContent = digits[i] || ""
      cell.classList.toggle("ring-2", focused && i === next)
      cell.classList.toggle("ring-pink-500", focused && i === next)
    })
  }
}
