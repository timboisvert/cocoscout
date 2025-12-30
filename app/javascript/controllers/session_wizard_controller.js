import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "addModal", "editModal", "addForm", "editForm",
        "editStartAt", "editDuration", "editLocationSelect",
        "generateIsOnline", "generateLocationSelect", "generateOnlineInfo",
        "addIsOnline", "addLocationSelect"
    ]

    connect() {
        // Add escape key listener for modals
        this.escapeListener = (e) => {
            if (e.key === "Escape") {
                this.closeAddModal()
                this.closeEditModal()
            }
        }
        document.addEventListener("keydown", this.escapeListener)
    }

    disconnect() {
        document.removeEventListener("keydown", this.escapeListener)
    }

    openAddModal(event) {
        event.preventDefault()
        event.stopPropagation()
        this.addModalTarget.classList.remove("hidden")
        // Focus the modal for keyboard events
        const focusable = this.addModalTarget.querySelector('[tabindex="-1"]')
        if (focusable) focusable.focus()
    }

    closeAddModal(event) {
        if (event) {
            event.preventDefault()
            event.stopPropagation()
        }
        this.addModalTarget.classList.add("hidden")
    }

    openEditModal(event) {
        event.preventDefault()
        event.stopPropagation()

        const button = event.currentTarget
        const sessionIndex = button.dataset.sessionIndex
        const startAt = button.dataset.sessionStartAt
        const duration = button.dataset.sessionDuration
        const locationId = button.dataset.sessionLocation

        // Populate the edit form
        if (this.hasEditStartAtTarget && startAt) {
            // Convert ISO string to datetime-local format
            const date = new Date(startAt)
            const localDatetime = date.toISOString().slice(0, 16)
            this.editStartAtTarget.value = localDatetime
        }

        if (this.hasEditDurationTarget && duration) {
            this.editDurationTarget.value = duration
        }

        if (this.hasEditLocationSelectTarget && locationId) {
            this.editLocationSelectTarget.value = locationId
        }

        // Update the form action URL
        if (this.hasEditFormTarget) {
            const baseUrl = this.editFormTarget.action.replace(/#$/, '')
            // Find the correct path pattern and update with session_index
            const production = window.location.pathname.match(/\/productions\/(\d+)/)?.[1]
            if (production) {
                this.editFormTarget.action = `/manage/audition_wizard/production/${production}/sessions/${sessionIndex}`
            }
        }

        this.editModalTarget.classList.remove("hidden")
        // Focus the modal for keyboard events
        const focusable = this.editModalTarget.querySelector('[tabindex="-1"]')
        if (focusable) focusable.focus()
    }

    closeEditModal(event) {
        if (event) {
            event.preventDefault()
            event.stopPropagation()
        }
        this.editModalTarget.classList.add("hidden")
    }
}
