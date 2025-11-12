import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["sessionCard", "actionButton"]

    connect() {
        // Select first session by default
        if (this.sessionCardTargets.length > 0) {
            this.selectSession(this.sessionCardTargets[0])
        }
    }

    selectSession(sessionCard) {
        // Remove active class from all cards
        this.sessionCardTargets.forEach(card => {
            card.classList.remove("ring-2", "ring-pink-500")
        })

        // Add active class to clicked card
        sessionCard.classList.add("ring-2", "ring-pink-500")

        // Update action buttons with current session ID
        const sessionId = sessionCard.getAttribute("data-session-id")
        this.updateActionButtons(sessionId)
    }

    updateActionButtons(sessionId) {
        const editBtn = this.element.querySelector("[data-action-type='edit']")
        const cancelBtn = this.element.querySelector("[data-action-type='cancel']")
        const duplicateBtn = this.element.querySelector("[data-action-type='duplicate']")
        const viewBtn = this.element.querySelector("[data-action-type='view']")

        const production = this.element.getAttribute("data-production-id")

        if (editBtn) editBtn.href = `/manage/productions/${production}/audition_sessions/${sessionId}/edit`
        if (cancelBtn) cancelBtn.href = `/manage/productions/${production}/audition_sessions/${sessionId}`
        if (duplicateBtn) duplicateBtn.href = `/manage/productions/${production}/audition_sessions/new?duplicate=${sessionId}`
        if (viewBtn) viewBtn.href = `/manage/productions/${production}/audition_sessions/${sessionId}`
    }
}
