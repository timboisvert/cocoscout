import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["formContainer", "title"]

    connect() {
        // Listen for successful Turbo visits
        document.addEventListener("turbo:load", this.handleTurboLoad.bind(this))
    }

    disconnect() {
        document.removeEventListener("turbo:load", this.handleTurboLoad.bind(this))
    }

    handleTurboLoad() {
        // If we're back on the prepare_audition_sessions page, refresh the list and reset form
        if (window.location.pathname.includes("prepare/audition_sessions")) {
            this.refreshSessionsList()
            this.resetForm()
        }
    }

    openEditForm(event) {
        event.preventDefault()
        const sessionId = event.currentTarget.dataset.sessionId
        const auditionCycleId = event.currentTarget.dataset.auditionCycleId
        const productionId = this.element.dataset.productionId

        // Fetch the edit form partial
        fetch(`/manage/productions/${productionId}/audition_cycles/${auditionCycleId}/audition_sessions/${sessionId}/edit`, {
            headers: {
                "X-Requested-With": "XMLHttpRequest"
            }
        })
            .then(response => response.text())
            .then(html => {
                this.formContainerTarget.innerHTML = html
                this.titleTarget.textContent = "Edit Audition Session"
            })
    }

    resetForm(event) {
        if (event) event.preventDefault()
        // Reset to new form
        const auditionCycleId = this.element.dataset.auditionCycleId
        const productionId = this.element.dataset.productionId
        fetch(`/manage/productions/${productionId}/audition_cycles/${auditionCycleId}/audition_sessions/new`, {
            headers: {
                "X-Requested-With": "XMLHttpRequest"
            }
        })
            .then(response => response.text())
            .then(html => {
                this.formContainerTarget.innerHTML = html
                this.titleTarget.textContent = "New Audition Session"
            })
    }

    refreshSessionsList() {
        const auditionCycleId = this.element.dataset.auditionCycleId
        const productionId = this.element.dataset.productionId
        // Fetch and update the sessions list
        fetch(`/manage/productions/${productionId}/audition_cycles/${auditionCycleId}/audition_sessions`)
            .then(response => response.text())
            .then(html => {
                // Extract just the sessions list from the response
                const parser = new DOMParser()
                const doc = parser.parseFromString(html, 'text/html')
                const newList = doc.querySelector('#audition_sessions_list')
                if (newList) {
                    document.querySelector('#audition_sessions_list').innerHTML = newList.innerHTML
                }
            })
    }
}
