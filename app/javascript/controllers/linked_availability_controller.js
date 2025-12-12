import { Controller } from "@hotwired/stimulus"

/**
 * Linked Availability Controller
 * 
 * Manages grouped availability for linked events (Options A & B).
 * When setting availability on a linked group, all shows in the group
 * are updated together.
 */
export default class extends Controller {
  static targets = ["showRow", "statusBadge", "detailsPanel", "expandButton"]
  static values = {
    entityKey: String,
    showIds: Array,
    status: String,
    expanded: { type: Boolean, default: false }
  }

  connect() {
    this.updateUI()
  }

  /**
   * Set the availability status for all shows in the group
   */
  async setStatus(event) {
    event.preventDefault()
    const newStatus = event.currentTarget.dataset.status
    
    // Disable buttons while updating
    this.element.classList.add("opacity-50", "pointer-events-none")
    
    try {
      // Update all shows in parallel
      await Promise.all(
        this.showIdsValue.map(showId => this.updateShowAvailability(showId, newStatus))
      )
      
      // Update local state
      this.statusValue = newStatus
      this.updateUI()
      
      // Dispatch event for any parent components
      this.dispatch("updated", { 
        detail: { 
          showIds: this.showIdsValue, 
          status: newStatus,
          entityKey: this.entityKeyValue
        }
      })
    } catch (error) {
      console.error("Failed to update availability:", error)
      // Could show an error toast here
    } finally {
      this.element.classList.remove("opacity-50", "pointer-events-none")
    }
  }

  /**
   * Toggle the details panel (Option A)
   */
  toggleDetails(event) {
    event.preventDefault()
    this.expandedValue = !this.expandedValue
  }

  expandedValueChanged() {
    if (this.hasDetailsPanelTarget) {
      if (this.expandedValue) {
        this.detailsPanelTarget.classList.remove("hidden")
      } else {
        this.detailsPanelTarget.classList.add("hidden")
      }
    }
    
    if (this.hasExpandButtonTarget) {
      // Rotate chevron
      const icon = this.expandButtonTarget.querySelector("svg")
      if (icon) {
        if (this.expandedValue) {
          icon.classList.add("rotate-180")
        } else {
          icon.classList.remove("rotate-180")
        }
      }
    }
  }

  /**
   * Update the UI to reflect current status
   */
  updateUI() {
    const status = this.statusValue
    
    // Update master button states
    this.element.querySelectorAll("[data-status]").forEach(btn => {
      const btnStatus = btn.dataset.status
      const isActive = btnStatus === status
      
      // Reset classes - use pink to match the regular availability buttons
      btn.classList.remove(
        "bg-pink-500", "text-white",
        "bg-white", "text-gray-700", "hover:bg-gray-50"
      )
      
      if (isActive) {
        btn.classList.add("bg-pink-500", "text-white")
      } else {
        btn.classList.add("bg-white", "text-gray-700", "hover:bg-gray-50")
      }
    })
    
    // Update individual status badges
    this.statusBadgeTargets.forEach(badge => {
      badge.textContent = status.charAt(0).toUpperCase() + status.slice(1)
      
      badge.classList.remove(
        "bg-green-100", "text-green-800",
        "bg-red-100", "text-red-800",
        "bg-gray-100", "text-gray-600"
      )
      
      if (status === "available") {
        badge.classList.add("bg-green-100", "text-green-800")
      } else if (status === "unavailable") {
        badge.classList.add("bg-red-100", "text-red-800")
      } else {
        badge.classList.add("bg-gray-100", "text-gray-600")
      }
    })
  }

  /**
   * Update availability for a single show via API
   */
  async updateShowAvailability(showId, status) {
    const csrfToken = document.querySelector("[name='csrf-token']")?.content
    
    const response = await fetch(`/my/availability/${showId}`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken,
        "Accept": "application/json"
      },
      body: JSON.stringify({
        entity_key: this.entityKeyValue,
        status: status
      })
    })
    
    if (!response.ok) {
      throw new Error(`Failed to update show ${showId}`)
    }
    
    return response.json()
  }
}
