import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="profile-section"
export default class extends Controller {
  static targets = ["content", "icon"]

  connect() {
    // Initialize collapsed state from data attribute
    const collapsed = this.element.dataset.collapsed === "true"
    if (collapsed) {
      this.contentTarget.classList.add("hidden")
      this.iconTarget.classList.add("rotate-180")
    }
  }

  toggle() {
    this.contentTarget.classList.toggle("hidden")
    this.iconTarget.classList.toggle("rotate-180")
    
    // Update data attribute for persistence
    const isCollapsed = this.contentTarget.classList.contains("hidden")
    this.element.dataset.collapsed = isCollapsed
  }
}
