import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bulkModal", "payEveryoneModal", "payeeCard", "progressText", "progressBar", "markPaidModal", "markPaidName", "markPaidForm"]
  static values = {
    payees: Array,
    currentIndex: { type: Number, default: 0 },
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

  // Mark individual as paid modal
  showMarkPaidModal(event) {
    event.preventDefault()
    const itemId = event.currentTarget.dataset.itemId
    const itemName = event.currentTarget.dataset.itemName
    this.currentItemIdValue = parseInt(itemId)

    // Update the name in the modal
    if (this.hasMarkPaidNameTarget) {
      this.markPaidNameTarget.textContent = itemName
    }

    // Update form actions with the correct item ID
    this.markPaidFormTargets.forEach(form => {
      const method = form.dataset.method
      const baseUrl = window.location.pathname
      form.action = `${baseUrl}/line_items/${itemId}/mark_paid?payment_method=${method}`
    })

    this.markPaidModalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  hideMarkPaidModal(event) {
    if (event) event.preventDefault()
    this.markPaidModalTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  // Pay Everyone Walkthrough
  showPayEveryoneModal(event) {
    event.preventDefault()
    this.currentIndexValue = 0
    this.updatePayeeDisplay()
    this.payEveryoneModalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  hidePayEveryoneModal(event) {
    if (event) event.preventDefault()
    this.payEveryoneModalTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  updatePayeeDisplay() {
    const payees = this.payeesValue
    const index = this.currentIndexValue
    const total = payees.length

    // Update progress
    if (this.hasProgressTextTarget) {
      this.progressTextTarget.textContent = `${index + 1} of ${total}`
    }
    if (this.hasProgressBarTarget) {
      const percent = ((index + 1) / total) * 100
      this.progressBarTarget.style.width = `${percent}%`
    }

    // Show only the current payee card
    this.payeeCardTargets.forEach((card, i) => {
      if (i === index) {
        card.classList.remove("hidden")
      } else {
        card.classList.add("hidden")
      }
    })
  }

  nextPayee(event) {
    if (event) event.preventDefault()
    if (this.currentIndexValue < this.payeesValue.length - 1) {
      this.currentIndexValue++
      this.updatePayeeDisplay()
    } else {
      // All done!
      this.hidePayEveryoneModal()
      // Reload to show updated status
      window.location.reload()
    }
  }

  previousPayee(event) {
    if (event) event.preventDefault()
    if (this.currentIndexValue > 0) {
      this.currentIndexValue--
      this.updatePayeeDisplay()
    }
  }

  // Open Venmo app with payment pre-filled
  openVenmo(event) {
    event.preventDefault()
    const button = event.currentTarget
    const handle = button.dataset.venmoHandle
    const amount = button.dataset.venmoAmount
    const note = button.dataset.venmoNote || ""

    // Venmo deep link - opens the Venmo app
    // Format: venmo://paycharge?txn=pay&recipients=handle&amount=X&note=Y
    const venmoUrl = `venmo://paycharge?txn=pay&recipients=${encodeURIComponent(handle)}&amount=${encodeURIComponent(amount)}&note=${encodeURIComponent(note)}`

    // Try to open Venmo app, fallback to web
    const webUrl = `https://venmo.com/${encodeURIComponent(handle)}?txn=pay&amount=${encodeURIComponent(amount)}&note=${encodeURIComponent(note)}`

    // Try the deep link first
    window.location.href = venmoUrl

    // After a short delay, if we're still here, open web version
    setTimeout(() => {
      window.open(webUrl, '_blank')
    }, 1500)
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
      if (this.hasPayEveryoneModalTarget && !this.payEveryoneModalTarget.classList.contains("hidden")) {
        this.hidePayEveryoneModal()
      }
      if (this.hasMarkPaidModalTarget && !this.markPaidModalTarget.classList.contains("hidden")) {
        this.hideMarkPaidModal()
      }
    }
  }

  // Close modal when clicking backdrop
  closeOnBackdrop(event) {
    if (event.target === this.bulkModalTarget) {
      this.hideBulkModal()
    }
    if (this.hasPayEveryoneModalTarget && event.target === this.payEveryoneModalTarget) {
      this.hidePayEveryoneModal()
    }
    if (this.hasMarkPaidModalTarget && event.target === this.markPaidModalTarget) {
      this.hideMarkPaidModal()
    }
  }
}
