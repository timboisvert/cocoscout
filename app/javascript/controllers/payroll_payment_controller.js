import { Controller } from "@hotwired/stimulus"

// Controls the payment walkthrough modal for payroll runs
export default class extends Controller {
  static targets = ["payEveryoneModal", "payeeCard", "progressText", "progressBar", "allDoneCard"]
  static values = {
    runId: Number,
    currentIndex: { type: Number, default: 0 }
  }

  connect() {
    this.totalPayees = this.payeeCardTargets.length
  }

  showPayEveryoneModal(event) {
    if (event) event.preventDefault()
    if (this.hasPayEveryoneModalTarget) {
      this.payEveryoneModalTarget.classList.remove("hidden")
      document.body.classList.add("overflow-hidden")
    }
  }

  hidePayEveryoneModal(event) {
    if (event) event.preventDefault()
    if (this.hasPayEveryoneModalTarget) {
      this.payEveryoneModalTarget.classList.add("hidden")
      document.body.classList.remove("overflow-hidden")
    }
  }

  closeOnBackdrop(event) {
    // Only close if clicking directly on the backdrop
    if (event.target === event.currentTarget) {
      this.hidePayEveryoneModal(event)
    }
  }

  closeOnEscape(event) {
    if (event.key === "Escape") {
      this.hidePayEveryoneModal(event)
    }
  }

  stopPropagation(event) {
    event.stopPropagation()
  }

  nextPayee(event) {
    // If this is a form submission, submit it via fetch first
    if (event && event.type === "submit") {
      event.preventDefault()
      const form = event.target

      // Submit the form via fetch
      fetch(form.action, {
        method: form.method,
        body: new FormData(form),
        headers: {
          "Accept": "text/html, application/xhtml+xml",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
        },
        credentials: "same-origin"
      }).then(() => {
        this.advanceToNextPayee()
      }).catch((error) => {
        console.error("Error marking as paid:", error)
        // Still advance even on error to not get stuck
        this.advanceToNextPayee()
      })
    } else {
      // Skip button - just advance without submitting
      if (event) event.preventDefault()
      this.advanceToNextPayee()
    }
  }

  skipPayee(event) {
    if (event) event.preventDefault()
    this.advanceToNextPayee()
  }

  previousPayee(event) {
    if (event) event.preventDefault()
    if (this.currentIndexValue <= 0) return

    const currentCard = this.payeeCardTargets[this.currentIndexValue]
    if (currentCard) {
      currentCard.classList.add("hidden")
    }

    this.currentIndexValue--

    const prevCard = this.payeeCardTargets[this.currentIndexValue]
    if (prevCard) {
      prevCard.classList.remove("hidden")
    }

    // Update progress
    if (this.hasProgressTextTarget) {
      this.progressTextTarget.textContent = `${this.currentIndexValue + 1} of ${this.totalPayees}`
    }
    if (this.hasProgressBarTarget) {
      const percentage = ((this.currentIndexValue + 1) / this.totalPayees * 100).toFixed(0)
      this.progressBarTarget.style.width = `${percentage}%`
    }
  }

  advanceToNextPayee() {
    const currentCard = this.payeeCardTargets[this.currentIndexValue]
    if (currentCard) {
      currentCard.classList.add("hidden")
    }

    this.currentIndexValue++

    if (this.currentIndexValue >= this.totalPayees) {
      // All done! Hide modal and reload to show updated status
      this.hidePayEveryoneModal()
      window.location.reload()
    } else {
      // Show next card
      const nextCard = this.payeeCardTargets[this.currentIndexValue]
      if (nextCard) {
        nextCard.classList.remove("hidden")
      }
      // Update progress
      if (this.hasProgressTextTarget) {
        this.progressTextTarget.textContent = `${this.currentIndexValue + 1} of ${this.totalPayees}`
      }
      if (this.hasProgressBarTarget) {
        const percentage = ((this.currentIndexValue + 1) / this.totalPayees * 100).toFixed(0)
        this.progressBarTarget.style.width = `${percentage}%`
      }
    }
  }

  openVenmo(event) {
    event.preventDefault()
    const button = event.currentTarget
    // Strip @ prefix if present - Venmo deep links don't want it
    const handle = (button.dataset.venmoHandle || "").replace(/^@/, "")
    const amount = button.dataset.venmoAmount
    const note = button.dataset.venmoNote || ""

    // Venmo deep link - opens the Venmo app
    // Format: venmo://paycharge?txn=pay&recipients=handle&amount=X&note=Y
    const venmoUrl = `venmo://paycharge?txn=pay&recipients=${encodeURIComponent(handle)}&amount=${encodeURIComponent(amount)}&note=${encodeURIComponent(note)}`

    // Web fallback URL
    const webUrl = `https://venmo.com/${encodeURIComponent(handle)}?txn=pay&amount=${encodeURIComponent(amount)}&note=${encodeURIComponent(note)}`

    // Try the deep link first
    window.location.href = venmoUrl

    // After a short delay, if we're still here, open web version
    setTimeout(() => {
      window.open(webUrl, '_blank')
    }, 1500)
  }
}
