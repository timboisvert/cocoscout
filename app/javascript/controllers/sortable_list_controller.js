import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="sortable-list"
// Provides move up/down functionality for list items
export default class extends Controller {
  static targets = ["list"]

  connect() {
    // No sortableJS needed - using up/down buttons for simplicity
  }

  moveUp(event) {
    const item = event.target.closest("[data-position]")
    const prev = item.previousElementSibling
    
    if (prev && prev.hasAttribute("data-position")) {
      item.parentNode.insertBefore(item, prev)
      this.updatePositions()
    }
  }

  moveDown(event) {
    const item = event.target.closest("[data-position]")
    const next = item.nextElementSibling
    
    if (next && next.hasAttribute("data-position")) {
      item.parentNode.insertBefore(next, item)
      this.updatePositions()
    }
  }

  updatePositions() {
    const items = this.listTarget.querySelectorAll("[data-position]")
    items.forEach((item, index) => {
      const input = item.querySelector("input[name*='[position]']")
      if (input) {
        input.value = index
      }
      item.dataset.position = index
    })
  }
}
