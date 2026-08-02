import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bulkModal", "markPaidModal", "markPaidName", "markPaidAmount", "markPaidForm", "addPersonModal", "addMissingCastModal", "issueAdvancesModal"]
  static values = {
    currentItemId: { type: Number, default: 0 }
  }

  showBulkModal(event) {
    event.preventDefault()
    this.bulkModalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  hideBulkModal(event) {
    if (event) event.preventDefault()
    this.bulkModalTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  // Add Person Modal
  showAddPersonModal(event) {
    event.preventDefault()
    if (this.hasAddPersonModalTarget) {
      this.addPersonModalTarget.classList.remove("hidden")
      document.body.classList.add("overflow-hidden")
    }
  }

  hideAddPersonModal(event) {
    if (event) event.preventDefault()
    if (this.hasAddPersonModalTarget) {
      this.addPersonModalTarget.classList.add("hidden")
      document.body.classList.remove("overflow-hidden")
    }
  }

  // Add Missing Cast Modal
  showAddMissingCastModal(event) {
    event.preventDefault()
    if (this.hasAddMissingCastModalTarget) {
      this.addMissingCastModalTarget.classList.remove("hidden")
      document.body.classList.add("overflow-hidden")
    }
  }

  hideAddMissingCastModal(event) {
    if (event) event.preventDefault()
    if (this.hasAddMissingCastModalTarget) {
      this.addMissingCastModalTarget.classList.add("hidden")
      document.body.classList.remove("overflow-hidden")
    }
  }

  // Issue Advances Modal
  showIssueAdvancesModal(event) {
    event.preventDefault()
    if (this.hasIssueAdvancesModalTarget) {
      this.issueAdvancesModalTarget.classList.remove("hidden")
      document.body.classList.add("overflow-hidden")
    }
  }

  hideIssueAdvancesModal(event) {
    if (event) event.preventDefault()
    if (this.hasIssueAdvancesModalTarget) {
      this.issueAdvancesModalTarget.classList.add("hidden")
      document.body.classList.remove("overflow-hidden")
    }
  }

  // Mark individual as paid modal
  showMarkPaidModal(event) {
    event.preventDefault()
    const itemId = event.currentTarget.dataset.itemId
    const itemName = event.currentTarget.dataset.itemName
    const itemAmount = event.currentTarget.dataset.itemAmount
    // Store the item ID(s) - may be comma-separated for grouped payees
    this.currentItemIdValue = itemId.includes(',') ? itemId : parseInt(itemId)

    // Update the name + amount in the modal
    if (this.hasMarkPaidNameTarget) {
      this.markPaidNameTarget.textContent = itemName
    }
    if (this.hasMarkPaidAmountTarget && itemAmount) {
      this.markPaidAmountTarget.textContent = itemAmount
    }

    // Point the (single) form at the right line item(s). The method + notes are
    // submitted from the form fields, so no query string is needed.
    const baseUrl = window.location.pathname
    this.markPaidFormTargets.forEach(form => {
      form.action = `${baseUrl}/line_items/${itemId}/mark_paid`
    })

    this.markPaidModalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  hideMarkPaidModal(event) {
    if (event) event.preventDefault()
    this.markPaidModalTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  // Close modal on escape key
  connect() {
    this.boundHandleKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.boundHandleKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandleKeydown)
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      if (this.hasBulkModalTarget && !this.bulkModalTarget.classList.contains("hidden")) {
        this.hideBulkModal()
      }
      if (this.hasMarkPaidModalTarget && !this.markPaidModalTarget.classList.contains("hidden")) {
        this.hideMarkPaidModal()
      }
      if (this.hasAddPersonModalTarget && !this.addPersonModalTarget.classList.contains("hidden")) {
        this.hideAddPersonModal()
      }
      if (this.hasAddMissingCastModalTarget && !this.addMissingCastModalTarget.classList.contains("hidden")) {
        this.hideAddMissingCastModal()
      }
    }
  }

  // Close modal when clicking backdrop
  closeOnBackdrop(event) {
    if (event.target === this.bulkModalTarget) {
      this.hideBulkModal()
    }
    if (this.hasMarkPaidModalTarget && event.target === this.markPaidModalTarget) {
      this.hideMarkPaidModal()
    }
    if (this.hasAddPersonModalTarget && event.target === this.addPersonModalTarget) {
      this.hideAddPersonModal()
    }
    if (this.hasAddMissingCastModalTarget && event.target === this.addMissingCastModalTarget) {
      this.hideAddMissingCastModal()
    }
  }
}
