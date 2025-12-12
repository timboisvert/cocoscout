import { Controller } from "@hotwired/stimulus"

/**
 * Linked Availability Modal Controller
 * 
 * Manages the confirmation modal for grouped availability (Option C).
 * Shows a modal listing all affected events before applying changes.
 */
export default class extends Controller {
  static targets = ["modal", "statusBadge", "statusText", "confirmButton"]
  static values = {
    entityKey: String,
    showIds: Array,
    linkageName: String,
    modalId: String,
    pendingStatus: String
  }

  connect() {
    // Close modal on escape key
    this.boundHandleKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.boundHandleKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandleKeydown)
  }

  handleKeydown(event) {
    if (event.key === "Escape" && this.isModalOpen()) {
      this.closeModal()
    }
  }

  isModalOpen() {
    return this.hasModalTarget && !this.modalTarget.classList.contains("hidden")
  }

  /**
   * Open the confirmation modal
   */
  openModal(event) {
    event.preventDefault()
    const status = event.currentTarget.dataset.status
    this.pendingStatusValue = status
    
    // Update modal content
    if (this.hasStatusTextTarget) {
      this.statusTextTarget.textContent = status
      
      // Color the status text
      this.statusTextTarget.classList.remove("text-green-600", "text-red-600")
      if (status === "available") {
        this.statusTextTarget.classList.add("text-green-600")
      } else if (status === "unavailable") {
        this.statusTextTarget.classList.add("text-red-600")
      }
    }
    
    // Update confirm button styling
    if (this.hasConfirmButtonTarget) {
      this.confirmButtonTarget.classList.remove("bg-green-600", "hover:bg-green-700", "bg-red-600", "hover:bg-red-700", "bg-pink-600", "hover:bg-pink-700")
      if (status === "available") {
        this.confirmButtonTarget.classList.add("bg-green-600", "hover:bg-green-700")
        this.confirmButtonTarget.textContent = "Set Available"
      } else if (status === "unavailable") {
        this.confirmButtonTarget.classList.add("bg-red-600", "hover:bg-red-700")
        this.confirmButtonTarget.textContent = "Set Unavailable"
      }
    }
    
    // Show modal
    if (this.hasModalTarget) {
      this.modalTarget.classList.remove("hidden")
      document.body.classList.add("overflow-hidden")
    }
  }

  /**
   * Close the modal without applying changes
   */
  closeModal(event) {
    if (event) event.preventDefault()
    
    if (this.hasModalTarget) {
      this.modalTarget.classList.add("hidden")
      document.body.classList.remove("overflow-hidden")
    }
    
    this.pendingStatusValue = ""
  }

  /**
   * Confirm and apply the status change
   */
  async confirmStatus(event) {
    event.preventDefault()
    
    const status = this.pendingStatusValue
    if (!status) return
    
    // Disable button while updating
    if (this.hasConfirmButtonTarget) {
      this.confirmButtonTarget.disabled = true
      this.confirmButtonTarget.textContent = "Updating..."
    }
    
    try {
      // Update all shows in parallel
      await Promise.all(
        this.showIdsValue.map(showId => this.updateShowAvailability(showId, status))
      )
      
      // Update the status badge
      this.updateStatusBadge(status)
      
      // Close modal
      this.closeModal()
      
      // Dispatch event for any parent components
      this.dispatch("updated", { 
        detail: { 
          showIds: this.showIdsValue, 
          status: status,
          entityKey: this.entityKeyValue
        }
      })
    } catch (error) {
      console.error("Failed to update availability:", error)
      // Could show an error message
    } finally {
      if (this.hasConfirmButtonTarget) {
        this.confirmButtonTarget.disabled = false
      }
    }
  }

  /**
   * Update the status badge display
   */
  updateStatusBadge(status) {
    if (!this.hasStatusBadgeTarget) return
    
    const badge = this.statusBadgeTarget
    
    // Update text
    badge.textContent = status.charAt(0).toUpperCase() + status.slice(1)
    
    // Update styling
    badge.classList.remove(
      "bg-green-100", "text-green-800",
      "bg-red-100", "text-red-800",
      "bg-yellow-100", "text-yellow-800",
      "bg-gray-100", "text-gray-600"
    )
    
    if (status === "available") {
      badge.classList.add("bg-green-100", "text-green-800")
    } else if (status === "unavailable") {
      badge.classList.add("bg-red-100", "text-red-800")
    } else {
      badge.classList.add("bg-gray-100", "text-gray-600")
    }
    
    // Update the dot indicator
    const dot = this.element.querySelector(".rounded-full.w-3.h-3")
    if (dot) {
      dot.classList.remove("bg-green-500", "bg-red-500", "bg-yellow-500", "bg-gray-300")
      if (status === "available") {
        dot.classList.add("bg-green-500")
      } else if (status === "unavailable") {
        dot.classList.add("bg-red-500")
      } else {
        dot.classList.add("bg-gray-300")
      }
    }
  }

  /**
   * Update availability for a single show via API
   */
  async updateShowAvailability(showId, status) {
    const csrfToken = document.querySelector("[name='csrf-token']")?.content
    
    const response = await fetch(`/shows/${showId}/availability`, {
      method: "POST",
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
