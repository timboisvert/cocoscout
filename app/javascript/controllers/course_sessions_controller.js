import { Controller } from "@hotwired/stimulus"

// Manages course session creation with single events and recurring series
export default class extends Controller {
    static targets = ["sessionsList", "singleTemplate", "recurringTemplate", "rulesJson"]

    connect() {
        this.sessions = []
        this._loadExistingSessions()
    }

    addSingleSession(event) {
        event.preventDefault()
        const defaultValues = this._smartDefaults()
        const template = this.singleTemplateTarget.content.cloneNode(true)
        const item = template.querySelector(".session-item")
        const index = this.sessions.length

        item.dataset.sessionIndex = index

        // Set smart defaults
        const datetimeInput = item.querySelector('[data-field="datetime"]')
        if (datetimeInput && defaultValues.datetime) {
            datetimeInput.value = defaultValues.datetime
        }

        const durationSelect = item.querySelector('[data-field="duration"]')
        if (durationSelect && defaultValues.duration) {
            durationSelect.value = defaultValues.duration
        }

        this.sessionsListTarget.appendChild(item)
        this.sessions.push({ type: "single", index })
        this._updateRulesJson()
    }

    addRecurringSeries(event) {
        event.preventDefault()
        const template = this.recurringTemplateTarget.content.cloneNode(true)
        const item = template.querySelector(".session-item")
        const index = this.sessions.length

        item.dataset.sessionIndex = index

        // Set default duration
        const defaultValues = this._smartDefaults()
        const durationSelect = item.querySelector('[data-field="duration"]')
        if (durationSelect && defaultValues.duration) {
            durationSelect.value = defaultValues.duration
        }

        this.sessionsListTarget.appendChild(item)
        this.sessions.push({ type: "recurring", index })
        this._updateRulesJson()
    }

    removeSession(event) {
        event.preventDefault()
        const item = event.currentTarget.closest(".session-item")
        const index = parseInt(item.dataset.sessionIndex)
        item.remove()
        this.sessions = this.sessions.filter(s => s.index !== index)
        this._updateRulesJson()
    }

    inputChanged() {
        this._updateRulesJson()
    }

    _smartDefaults() {
        // Look at existing sessions to determine smart defaults
        const items = this.sessionsListTarget.querySelectorAll(".session-item")
        let lastDatetime = null
        let lastDuration = "60"

        items.forEach(item => {
            const dtInput = item.querySelector('[data-field="datetime"]')
            const durSelect = item.querySelector('[data-field="duration"]')
            if (dtInput && dtInput.value) lastDatetime = dtInput.value
            if (durSelect && durSelect.value) lastDuration = durSelect.value
        })

        let nextDatetime = null
        if (lastDatetime) {
            // Add 7 days to the last session (assume weekly)
            const dt = new Date(lastDatetime)
            dt.setDate(dt.getDate() + 7)
            nextDatetime = this._formatDatetimeLocal(dt)
        } else {
            // Default to next week, 7pm
            const now = new Date()
            now.setDate(now.getDate() + ((7 - now.getDay()) % 7 || 7)) // next week same day, or +7
            now.setHours(19, 0, 0, 0)
            nextDatetime = this._formatDatetimeLocal(now)
        }

        return { datetime: nextDatetime, duration: lastDuration }
    }

    _formatDatetimeLocal(date) {
        const year = date.getFullYear()
        const month = String(date.getMonth() + 1).padStart(2, "0")
        const day = String(date.getDate()).padStart(2, "0")
        const hours = String(date.getHours()).padStart(2, "0")
        const minutes = String(date.getMinutes()).padStart(2, "0")
        return `${year}-${month}-${day}T${hours}:${minutes}`
    }

    _loadExistingSessions() {
        // Load from existing hidden inputs if any
        const items = this.sessionsListTarget.querySelectorAll(".session-item")
        items.forEach((item, i) => {
            item.dataset.sessionIndex = i
            this.sessions.push({ type: item.dataset.sessionType || "single", index: i })
        })
        // Sync the hidden JSON input with what's on the page
        if (items.length > 0) {
            this._updateRulesJson()
        }
    }

    _updateRulesJson() {
        if (!this.hasRulesJsonTarget) return

        const rules = []
        const items = this.sessionsListTarget.querySelectorAll(".session-item")

        items.forEach(item => {
            const type = item.dataset.sessionType || "single"

            if (type === "single") {
                const datetime = item.querySelector('[data-field="datetime"]')?.value || ""
                const duration = item.querySelector('[data-field="duration"]')?.value || "60"
                if (datetime) {
                    rules.push({ type: "single", datetime, duration_minutes: parseInt(duration) })
                }
            } else if (type === "recurring") {
                const frequency = item.querySelector('[data-field="frequency"]')?.value || "weekly"
                const dayOfWeek = item.querySelector('[data-field="day_of_week"]')?.value || "1"
                const time = item.querySelector('[data-field="time"]')?.value || "19:00"
                const duration = item.querySelector('[data-field="duration"]')?.value || "60"
                const startDate = item.querySelector('[data-field="start_date"]')?.value || ""
                const endDate = item.querySelector('[data-field="end_date"]')?.value || ""

                if (startDate && endDate) {
                    rules.push({
                        type: "recurring",
                        frequency,
                        day_of_week: parseInt(dayOfWeek),
                        time,
                        duration_minutes: parseInt(duration),
                        start_date: startDate,
                        end_date: endDate
                    })
                }
            }
        })

        this.rulesJsonTarget.value = JSON.stringify(rules)
    }
}
