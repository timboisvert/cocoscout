import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["statusButtons", "presentCount", "absentCount", "lateCount", "excusedCount"]
    static values = { updateUrl: String }

    connect() {
        this.pendingChanges = {}
        this.boundHandleKeydown = this.handleKeydown.bind(this)
        document.addEventListener("keydown", this.boundHandleKeydown)
    }

    disconnect() {
        document.removeEventListener("keydown", this.boundHandleKeydown)
    }

    handleKeydown(event) {
        if (event.key === "Escape") {
            window.history.back()
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    get csrfToken() {
        return document.querySelector('meta[name="csrf-token"]')?.content
    }

    setStatus(event) {
        const button = event.currentTarget
        const status = button.dataset.status
        const container = button.closest('[data-attendance-modal-target="statusButtons"]')
        const assignmentId = container.dataset.assignmentId

        // Update button styling
        container.querySelectorAll('button').forEach(btn => {
            const btnStatus = btn.dataset.status
            btn.classList.remove('bg-green-500', 'bg-red-500', 'bg-yellow-500', 'bg-blue-500', 'text-white')
            btn.classList.add('bg-white', 'text-gray-600', 'border', 'border-gray-300')

            if (btn === button) {
                btn.classList.remove('bg-white', 'text-gray-600', 'border-gray-300')
                btn.classList.add('text-white')
                switch (btnStatus) {
                    case 'present': btn.classList.add('bg-green-500'); break
                    case 'absent': btn.classList.add('bg-red-500'); break
                    case 'late': btn.classList.add('bg-yellow-500'); break
                    case 'excused': btn.classList.add('bg-blue-500'); break
                }
            }
        })

        // Track the change
        this.pendingChanges[assignmentId] = status
        this.updateCounts()
    }

    markAllPresent() {
        this.statusButtonsTargets.forEach(container => {
            const presentBtn = container.querySelector('[data-status="present"]')
            if (presentBtn) {
                presentBtn.click()
            }
        })
    }

    clearAll() {
        this.statusButtonsTargets.forEach(container => {
            const assignmentId = container.dataset.assignmentId
            container.querySelectorAll('button').forEach(btn => {
                btn.classList.remove('bg-green-500', 'bg-red-500', 'bg-yellow-500', 'bg-blue-500', 'text-white')
                btn.classList.add('bg-white', 'text-gray-600', 'border', 'border-gray-300')
            })
            this.pendingChanges[assignmentId] = 'unknown'
        })
        this.updateCounts()
    }

    updateCounts() {
        let present = 0, absent = 0, late = 0, excused = 0

        this.statusButtonsTargets.forEach(container => {
            const selectedBtn = container.querySelector('.bg-green-500, .bg-red-500, .bg-yellow-500, .bg-blue-500')
            if (selectedBtn) {
                const status = selectedBtn.dataset.status
                switch (status) {
                    case 'present': present++; break
                    case 'absent': absent++; break
                    case 'late': late++; break
                    case 'excused': excused++; break
                }
            }
        })

        if (this.hasPresentCountTarget) this.presentCountTarget.textContent = present
        if (this.hasAbsentCountTarget) this.absentCountTarget.textContent = absent
        if (this.hasLateCountTarget) this.lateCountTarget.textContent = late
        if (this.hasExcusedCountTarget) this.excusedCountTarget.textContent = excused
    }

    async save() {
        if (!this.hasUpdateUrlValue) return

        // Collect all current statuses
        const attendance = {}
        this.statusButtonsTargets.forEach(container => {
            const assignmentId = container.dataset.assignmentId
            const selectedBtn = container.querySelector('.bg-green-500, .bg-red-500, .bg-yellow-500, .bg-blue-500')
            if (selectedBtn) {
                attendance[assignmentId] = selectedBtn.dataset.status
            } else {
                attendance[assignmentId] = 'unknown'
            }
        })

        try {
            const response = await fetch(this.updateUrlValue, {
                method: "PATCH",
                headers: {
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                    "X-CSRF-Token": this.csrfToken
                },
                body: JSON.stringify({ attendance })
            })

            if (response.ok) {
                // Redirect back to the show edit page
                window.location.href = response.url || document.referrer
            } else {
                console.error("Failed to save attendance")
                alert("Failed to save attendance. Please try again.")
            }
        } catch (error) {
            console.error("Failed to save attendance:", error)
            alert("Failed to save attendance. Please try again.")
        }
    }
}
