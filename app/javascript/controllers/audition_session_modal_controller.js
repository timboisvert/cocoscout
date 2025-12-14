import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "formContainer", "title"]

    connect() {
        // Listen for successful form submissions
        document.addEventListener("turbo:submit-end", this.handleSubmitEnd.bind(this))
    }

    disconnect() {
        document.removeEventListener("turbo:submit-end", this.handleSubmitEnd.bind(this))
    }

    openNewModal(event) {
        event.preventDefault()
        const productionId = this.element.dataset.productionId
        const auditionCycleId = this.element.dataset.auditionCycleId

        // Fetch the new session form
        fetch(`/manage/productions/${productionId}/audition_cycles/${auditionCycleId}/audition_sessions/new`, {
            headers: {
                "X-Requested-With": "XMLHttpRequest"
            }
        })
            .then(response => response.text())
            .then(html => {
                this.formContainerTarget.innerHTML = html
                this.titleTarget.textContent = "New Audition Session"
                this.open()
            })
    }

    openEditModal(event) {
        event.preventDefault()
        const sessionId = event.currentTarget.dataset.sessionId
        const auditionCycleId = event.currentTarget.dataset.auditionCycleId
        const productionId = this.element.dataset.productionId

        // Fetch the edit session form
        fetch(`/manage/productions/${productionId}/audition_cycles/${auditionCycleId}/audition_sessions/${sessionId}/edit`, {
            headers: {
                "X-Requested-With": "XMLHttpRequest"
            }
        })
            .then(response => response.text())
            .then(html => {
                this.formContainerTarget.innerHTML = html
                this.titleTarget.textContent = "Edit Audition Session"
                this.open()
            })
    }

    open() {
        this.modalTarget.classList.remove("hidden")
        document.body.style.overflow = "hidden"
    }

    close() {
        this.modalTarget.classList.add("hidden")
        document.body.style.overflow = ""
    }

    closeOnBackdrop(event) {
        if (event.target === this.modalTarget) {
            this.close()
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    handleSubmitEnd(event) {
        // Check if the form submission was successful and was for an audition session
        if (event.detail.success && event.target.action.includes("audition_sessions")) {
            this.close()
            // Reload the page to show the updated list
            window.location.reload()
        }
    }
}
