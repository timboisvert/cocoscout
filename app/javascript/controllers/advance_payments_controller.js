import { Controller } from "@hotwired/stimulus"

// Controls the Pay Advances walkthrough modal
export default class extends Controller {
    static targets = ["modal", "card", "doneCard", "progressBar", "progressText"]
    static values = { advances: Array }

    connect() {
        this.currentIndex = 0
        this.totalCount = this.cardTargets.length
        this.madeChanges = false
    }

    openModal(event) {
        event.preventDefault()
        this.currentIndex = 0
        this.madeChanges = false
        this.updateProgress()
        this.showCurrentCard()
        this.modalTarget.classList.remove("hidden")
        document.body.style.overflow = "hidden"
    }

    closeModal(event) {
        if (event) event.preventDefault()
        this.modalTarget.classList.add("hidden")
        document.body.style.overflow = ""

        // Reload the page if any changes were made to update the UI
        if (this.madeChanges) {
            window.location.reload()
        }
    }

    closeOnBackdrop(event) {
        if (event.target === this.modalTarget) {
            this.closeModal(event)
        }
    }

    async markPaid(event) {
        event.preventDefault()

        const form = event.target.closest("form")
        if (!form) return

        const button = event.target.closest("button")
        if (button) {
            button.disabled = true
            button.textContent = "..."
        }

        try {
            const response = await fetch(form.action, {
                method: "POST",
                body: new FormData(form),
                headers: {
                    "Accept": "text/html",
                    "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
                }
            })

            if (response.ok) {
                // Track that we made changes
                this.madeChanges = true
                // Mark the current card as paid and move to next
                this.nextCard()
            } else {
                console.error("Failed to mark advance as paid")
                if (button) {
                    button.disabled = false
                    button.textContent = form.querySelector('input[name="payment_method"]')?.value?.replace(/^\w/, c => c.toUpperCase()) || "Retry"
                }
            }
        } catch (error) {
            console.error("Error marking advance as paid:", error)
            if (button) {
                button.disabled = false
            }
        }
    }

    skipPerson(event) {
        event.preventDefault()
        this.nextCard()
    }

    nextCard() {
        // Hide current card
        if (this.currentIndex < this.totalCount) {
            this.cardTargets[this.currentIndex].classList.add("hidden")
        }

        this.currentIndex++
        this.updateProgress()

        if (this.currentIndex >= this.totalCount) {
            // Show done state
            this.showDoneCard()
        } else {
            this.showCurrentCard()
        }
    }

    showCurrentCard() {
        this.cardTargets.forEach((card, index) => {
            card.classList.toggle("hidden", index !== this.currentIndex)
        })
        this.doneCardTarget.classList.add("hidden")
    }

    showDoneCard() {
        this.cardTargets.forEach(card => card.classList.add("hidden"))
        this.doneCardTarget.classList.remove("hidden")
    }

    updateProgress() {
        const completed = this.currentIndex
        const total = this.totalCount
        const percentage = total > 0 ? (completed / total) * 100 : 0

        this.progressBarTarget.style.width = `${percentage}%`
        this.progressTextTarget.textContent = `${completed} of ${total}`
    }
}
