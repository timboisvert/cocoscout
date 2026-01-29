import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "list", "loading", "emptyState", "presentCount", "totalCount", "walkinForm", "walkinNameInput", "walkinEmailInput", "walkinList", "walkinError", "walkinSuccess"]
    static values = {
        showId: Number,
        productionId: Number,
        attendanceUrl: String,
        updateUrl: String,
        createWalkinUrl: String
    }

    connect() {
        this.boundHandleKeydown = this.handleKeydown.bind(this)
        document.addEventListener("keydown", this.boundHandleKeydown)
        this.walkinRecords = []
    }

    disconnect() {
        document.removeEventListener("keydown", this.boundHandleKeydown)
    }

    handleKeydown(event) {
        if (event.key === "Escape" && this.hasModalTarget && !this.modalTarget.classList.contains("hidden")) {
            this.closeModal()
        }
    }

    async openModal(event) {
        if (event) event.preventDefault()
        if (this.hasModalTarget) {
            this.modalTarget.classList.remove("hidden")
            document.body.classList.add("overflow-hidden")
            this.walkinRecords = []
            this.clearMessages()
            await this.loadAttendance()
        }
    }

    closeModal() {
        if (this.hasModalTarget) {
            this.modalTarget.classList.add("hidden")
            document.body.classList.remove("overflow-hidden")
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    toggleWalkinForm() {
        if (this.hasWalkinFormTarget) {
            this.walkinFormTarget.classList.toggle("hidden")
            this.clearMessages()
        }
    }

    clearMessages() {
        if (this.hasWalkinErrorTarget) {
            this.walkinErrorTarget.classList.add("hidden")
            this.walkinErrorTarget.textContent = ""
        }
        if (this.hasWalkinSuccessTarget) {
            this.walkinSuccessTarget.classList.add("hidden")
            this.walkinSuccessTarget.textContent = ""
        }
    }

    showError(message) {
        if (this.hasWalkinErrorTarget) {
            this.walkinErrorTarget.textContent = message
            this.walkinErrorTarget.classList.remove("hidden")
        }
        if (this.hasWalkinSuccessTarget) {
            this.walkinSuccessTarget.classList.add("hidden")
        }
    }

    showSuccess(message) {
        if (this.hasWalkinSuccessTarget) {
            this.walkinSuccessTarget.textContent = message
            this.walkinSuccessTarget.classList.remove("hidden")
        }
        if (this.hasWalkinErrorTarget) {
            this.walkinErrorTarget.classList.add("hidden")
        }
        // Auto-hide success after 3 seconds
        setTimeout(() => {
            if (this.hasWalkinSuccessTarget) {
                this.walkinSuccessTarget.classList.add("hidden")
            }
        }, 3000)
    }

    addWalkin() {
        this.clearMessages()
        const nameInput = this.walkinNameInputTarget
        const emailInput = this.walkinEmailInputTarget
        const email = emailInput?.value?.trim()
        const name = nameInput?.value?.trim()

        if (!email) {
            this.showError("Please enter an email address")
            return
        }

        // Basic email validation
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
        if (!emailRegex.test(email)) {
            this.showError("Please enter a valid email address")
            return
        }

        // Check for duplicate in pending list
        if (this.walkinRecords.some(r => r.email.toLowerCase() === email.toLowerCase())) {
            this.showError("This email is already in your walk-in list")
            return
        }

        const walkinRecord = {
            id: `walkin_${Date.now()}_${Math.random()}`,
            name: name || email.split("@")[0],
            email,
            initials: this.getInitials(name || email)
        }

        this.walkinRecords.push(walkinRecord)

        if (nameInput) nameInput.value = ""
        if (emailInput) emailInput.value = ""

        this.renderWalkinList()
        this.updateCounts()
    }

    renderWalkinList() {
        if (!this.hasWalkinListTarget) return

        this.walkinListTarget.innerHTML = this.walkinRecords
            .map(record => this.renderWalkinRow(record))
            .join("")
    }

    renderWalkinRow(record) {
        return `
      <div class="flex items-center justify-between py-2 px-3 bg-white border border-gray-200 rounded-lg">
        <div class="flex items-center gap-3">
          <div class="w-8 h-8 rounded-lg bg-blue-100 flex items-center justify-center text-xs font-bold text-blue-600">
            ${record.initials}
          </div>
          <div>
            <p class="text-sm font-medium text-gray-900">${record.name}</p>
            <p class="text-xs text-gray-500">${record.email}</p>
          </div>
        </div>
        <button type="button"
                data-action="click->attendance-modal#removeWalkin"
                data-walkin-id="${record.id}"
                class="text-gray-400 hover:text-red-500 cursor-pointer">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
          </svg>
        </button>
      </div>
    `
    }

    removeWalkin(event) {
        const walkinId = event.target.closest("button").dataset.walkinId
        this.walkinRecords = this.walkinRecords.filter(r => r.id !== walkinId)
        this.renderWalkinList()
        this.updateCounts()
        this.clearMessages()
    }

    async submitWalkins(event) {
        this.clearMessages()

        if (this.walkinRecords.length === 0) {
            this.showError("Add at least one walk-in before submitting")
            return
        }

        const submitButton = event.target.closest("button")
        submitButton.disabled = true
        const originalText = submitButton.textContent
        submitButton.textContent = "Submitting..."

        const errors = []
        const successes = []

        try {
            for (const walkin of this.walkinRecords) {
                const response = await fetch(this.createWalkinUrlValue, {
                    method: "POST",
                    headers: {
                        "Accept": "application/json",
                        "Content-Type": "application/json",
                        "X-CSRF-Token": this.csrfToken
                    },
                    body: JSON.stringify({
                        name: walkin.name,
                        email: walkin.email
                    })
                })

                const data = await response.json()

                if (response.ok && data.success) {
                    successes.push(walkin.name)
                    // Remove successful walkin from list
                    this.walkinRecords = this.walkinRecords.filter(r => r.id !== walkin.id)
                } else {
                    const errorMsg = data.error || "Unknown error"
                    errors.push(`${walkin.name}: ${errorMsg}`)
                }
            }

            // Update the UI
            this.renderWalkinList()
            this.updateCounts()

            if (successes.length > 0) {
                await this.loadAttendance()
            }

            if (errors.length > 0) {
                this.showError(errors.join(". "))
            } else if (successes.length > 0) {
                this.showSuccess(`${successes.length} walk-in${successes.length > 1 ? "s" : ""} added successfully!`)
                this.walkinFormTarget.classList.add("hidden")
            }
        } catch (error) {
            console.error("Failed to submit walk-ins:", error)
            this.showError("Network error. Please check your connection and try again.")
        } finally {
            submitButton.disabled = false
            submitButton.textContent = originalText
        }
    }

    get csrfToken() {
        return document.querySelector('meta[name="csrf-token"]')?.content
    }

    async loadAttendance() {
        if (!this.hasAttendanceUrlValue) return

        this.showLoading()

        try {
            const response = await fetch(this.attendanceUrlValue, {
                headers: {
                    "Accept": "application/json",
                    "X-CSRF-Token": this.csrfToken
                }
            })

            if (response.ok) {
                const data = await response.json()
                this.renderAttendance(data.records)
            } else {
                console.error("Failed to load attendance")
                this.showEmptyState()
            }
        } catch (error) {
            console.error("Failed to load attendance:", error)
            this.showEmptyState()
        }
    }

    showLoading() {
        if (this.hasLoadingTarget) this.loadingTarget.classList.remove("hidden")
        if (this.hasListTarget) this.listTarget.classList.add("hidden")
        if (this.hasEmptyStateTarget) this.emptyStateTarget.classList.add("hidden")
    }

    showEmptyState() {
        if (this.hasLoadingTarget) this.loadingTarget.classList.add("hidden")
        if (this.hasListTarget) this.listTarget.classList.add("hidden")
        if (this.hasEmptyStateTarget) this.emptyStateTarget.classList.remove("hidden")
    }

    renderAttendance(records) {
        if (this.hasLoadingTarget) this.loadingTarget.classList.add("hidden")

        if (!records || records.length === 0) {
            this.showEmptyState()
            return
        }

        if (this.hasEmptyStateTarget) this.emptyStateTarget.classList.add("hidden")
        if (this.hasListTarget) {
            this.listTarget.classList.remove("hidden")
            this.listTarget.innerHTML = records.map(record => this.renderPersonRow(record)).join("")
        }

        this.updateCounts()
    }

    renderPersonRow(record) {
        const person = record.person
        const isPresent = record.record?.status === "present"
        const assignmentId = record.assignment.id
        const name = person?.name || "Unknown"
        const roleName = record.assignment?.role?.name || ""
        const headshotUrl = person?.headshot_url
        const initials = person?.initials || name.charAt(0).toUpperCase()

        const headshotHtml = headshotUrl
            ? `<img src="${headshotUrl}" alt="${name}" class="w-10 h-10 object-cover rounded-lg">`
            : `<div class="w-10 h-10 rounded-lg bg-gray-200 flex items-center justify-center text-xs font-bold text-gray-600">${initials}</div>`

        return `
      <div class="flex items-center justify-between py-3 px-3 border border-gray-100 rounded-lg hover:bg-gray-50">
        <div class="flex items-center gap-3">
          ${headshotHtml}
          <div>
            <p class="text-sm font-medium text-gray-900">${name}</p>
            ${roleName ? `<p class="text-xs text-gray-500">${roleName}</p>` : ""}
          </div>
        </div>
        <label class="relative inline-flex items-center cursor-pointer">
          <input type="checkbox"
                 ${isPresent ? "checked" : ""}
                 data-assignment-id="${assignmentId}"
                 data-action="change->attendance-modal#togglePresent"
                 class="sr-only peer">
          <div class="w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-pink-300 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-pink-500"></div>
        </label>
      </div>
    `
    }

    updateCounts() {
        if (!this.hasListTarget) return

        const checkboxes = this.listTarget.querySelectorAll('input[type="checkbox"]')
        const total = checkboxes.length + this.walkinRecords.length
        const present = Array.from(checkboxes).filter(cb => cb.checked).length + this.walkinRecords.length

        if (this.hasPresentCountTarget) this.presentCountTarget.textContent = present
        if (this.hasTotalCountTarget) this.totalCountTarget.textContent = total
    }

    async togglePresent(event) {
        const checkbox = event.target
        const assignmentId = checkbox.dataset.assignmentId
        const status = checkbox.checked ? "present" : "absent"

        if (!this.hasUpdateUrlValue) return

        try {
            const response = await fetch(this.updateUrlValue, {
                method: "PATCH",
                headers: {
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                    "X-CSRF-Token": this.csrfToken
                },
                body: JSON.stringify({ attendance: { [assignmentId]: status } })
            })

            if (response.ok) {
                this.updateCounts()
            } else {
                checkbox.checked = !checkbox.checked
                console.error("Failed to update attendance")
            }
        } catch (error) {
            checkbox.checked = !checkbox.checked
            console.error("Failed to update attendance:", error)
        }
    }

    markAllPresent() {
        if (!this.hasListTarget) return

        const checkboxes = this.listTarget.querySelectorAll('input[type="checkbox"]:not(:checked)')
        checkboxes.forEach(checkbox => {
            checkbox.checked = true
            checkbox.dispatchEvent(new Event('change', { bubbles: true }))
        })
    }

    getInitials(name) {
        return name
            .trim()
            .split(/\s+/)
            .slice(0, 2)
            .map(part => part[0].toUpperCase())
            .join("")
    }
}
