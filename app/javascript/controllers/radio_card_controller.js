import { Controller } from "@hotwired/stimulus"

// Simple controller to style radio button cards and show/hide extras
export default class extends Controller {
  static targets = ["card", "extras"]

  select(event) {
    const selectedValue = event.target.value
    const selectedCard = event.target.closest("[data-radio-card-target='card']")

    // Update card styles
    this.cardTargets.forEach(card => {
      if (card === selectedCard) {
        card.classList.remove("border-gray-200")
        card.classList.add("border-pink-500", "bg-pink-50")
      } else {
        card.classList.remove("border-pink-500", "bg-pink-50")
        card.classList.add("border-gray-200")
      }
    })

    // Show/hide extras (like production dropdowns)
    this.extrasTargets.forEach(el => {
      if (el.dataset.for === selectedValue) {
        el.classList.remove("hidden")
      } else {
        el.classList.add("hidden")
      }
    })
  }
}
