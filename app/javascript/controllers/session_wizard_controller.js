import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "addModal", "editModal", "addForm", "editForm",
        "editStartAt", "editDuration", "editLocationSelect",
        "generateIsOnline", "generateLocationSelect", "generateOnlineInfo",
        "addIsOnline", "addLocationSelect"
    ]
    static values = { editUrlTemplate: String }

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

        if (this.hasEditStartAtTarget && startAt) {
            // Convert ISO string to the value format <input type="datetime-local"> expects:
            // YYYY-MM-DDTHH:MM in the browser's local timezone.
            const date = new Date(startAt)
            const pad = (n) => String(n).padStart(2, '0')
            const localDatetime = `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`
            this.editStartAtTarget.value = localDatetime
        }

        if (this.hasEditDurationTarget && duration) {
            this.editDurationTarget.value = duration
        }

        if (this.hasEditLocationSelectTarget && locationId) {
            this.editLocationSelectTarget.value = locationId
        }

        // Update the form action URL using the server-provided template.
        // Template contains :session_index placeholder.
        if (this.hasEditFormTarget && this.hasEditUrlTemplateValue) {
            this.editFormTarget.action = this.editUrlTemplateValue.replace(":session_index", sessionIndex)
        }

        this.editModalTarget.classList.remove("hidden")
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
