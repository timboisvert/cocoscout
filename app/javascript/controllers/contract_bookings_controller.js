import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        // Mode selection
        "singleModeBtn", "multipleModeBtn", "singleModeContent", "multipleModeContent",
        "bookingMode", "rulesJson",
        // Single mode fields
        "singleLocation", "singleSpace", "singleDateTime", "singleDuration", "singleNotes",
        // Multiple mode
        "bookingsList", "formError",
        // Templates
        "singleEventTemplate", "recurringEventTemplate"
    ]
    static values = {
        locations: Array,
        existingRules: Array,
        initialMode: { type: String, default: "single" },
        defaultLocationId: { type: Number, default: 0 }
    }

    connect() {
        this.rules = this.existingRulesValue || []
        this.bookingIndex = 0

        // Use requestAnimationFrame to ensure DOM is fully ready
        requestAnimationFrame(() => {
            // Populate single mode space dropdown if location is selected (including default)
            if (this.hasSingleLocationTarget && this.hasSingleSpaceTarget) {
                const locationId = this.singleLocationTarget.value
                if (locationId) {
                    this.updateSpaceDropdown(this.singleSpaceTarget, locationId)

                    // Select saved space_id if exists
                    const singleRule = this.rules.find(r => r.mode === "single")
                    if (singleRule && singleRule.space_id) {
                        this.singleSpaceTarget.value = singleRule.space_id
                    }
                }
            }
        })

        // If in multiple mode, render existing rules
        if (this.initialModeValue === "multiple") {
            this.renderExistingRules()
        }
    }

    // ==================== MODE SELECTION ====================

    selectSingleMode() {
        this.bookingModeTarget.value = "single"

        // Update button styles
        this.singleModeBtnTarget.classList.remove("bg-white", "text-gray-700", "border-gray-300")
        this.singleModeBtnTarget.classList.add("bg-pink-500", "text-white", "border-pink-500")
        this.multipleModeBtnTarget.classList.remove("bg-pink-500", "text-white", "border-pink-500")
        this.multipleModeBtnTarget.classList.add("bg-white", "text-gray-700", "border-gray-300")

        // Show/hide content
        this.singleModeContentTarget.classList.remove("hidden")
        this.multipleModeContentTarget.classList.add("hidden")
    }

    selectMultipleMode() {
        this.bookingModeTarget.value = "multiple"

        // Update button styles
        this.multipleModeBtnTarget.classList.remove("bg-white", "text-gray-700", "border-gray-300")
        this.multipleModeBtnTarget.classList.add("bg-pink-500", "text-white", "border-pink-500")
        this.singleModeBtnTarget.classList.remove("bg-pink-500", "text-white", "border-pink-500")
        this.singleModeBtnTarget.classList.add("bg-white", "text-gray-700", "border-gray-300")

        // Show/hide content
        this.multipleModeContentTarget.classList.remove("hidden")
        this.singleModeContentTarget.classList.add("hidden")

        // If no bookings yet, add one single event to start
        if (this.bookingsListTarget.children.length === 0 && this.rules.length === 0) {
            // Don't auto-add, let user click
        }
    }

    // ==================== SINGLE MODE ====================

    singleLocationChanged() {
        this.updateSpaceDropdown(this.singleSpaceTarget, this.singleLocationTarget.value)
    }

    // ==================== MULTIPLE MODE ====================

    addSingleEvent() {
        const template = this.singleEventTemplateTarget
        const clone = template.content.cloneNode(true)
        const item = clone.querySelector(".booking-item")

        item.dataset.bookingIndex = this.bookingIndex++

        // Pre-select default location and populate spaces
        const locationSelect = clone.querySelector('[data-field="location_id"]')
        const spaceSelect = clone.querySelector('[data-field="space_id"]')
        if (locationSelect && this.defaultLocationIdValue) {
            locationSelect.value = this.defaultLocationIdValue
            if (spaceSelect) {
                this.updateSpaceDropdown(spaceSelect, this.defaultLocationIdValue)
            }
        }

        this.bookingsListTarget.appendChild(clone)

        // Focus the date/time input since location is pre-selected
        const dateTimeInput = this.bookingsListTarget.lastElementChild.querySelector('[data-field="starts_at"]')
        if (dateTimeInput) dateTimeInput.focus()
    }

    addRecurringSeries() {
        const template = this.recurringEventTemplateTarget
        const clone = template.content.cloneNode(true)
        const item = clone.querySelector(".booking-item")

        item.dataset.bookingIndex = this.bookingIndex++

        // Pre-select default location and populate spaces
        const locationSelect = clone.querySelector('[data-field="location_id"]')
        const spaceSelect = clone.querySelector('[data-field="space_id"]')
        if (locationSelect && this.defaultLocationIdValue) {
            locationSelect.value = this.defaultLocationIdValue
            if (spaceSelect) {
                this.updateSpaceDropdown(spaceSelect, this.defaultLocationIdValue)
            }
        }

        this.bookingsListTarget.appendChild(clone)

        // Focus the start date input since location is pre-selected
        const startDateInput = this.bookingsListTarget.lastElementChild.querySelector('[data-field="start_date"]')
        if (startDateInput) startDateInput.focus()
    }

    removeBooking(event) {
        const item = event.currentTarget.closest(".booking-item")
        if (item) {
            item.remove()
        }
    }

    frequencyChanged(event) {
        const item = event.currentTarget.closest(".booking-item")
        const frequency = event.currentTarget.value

        const dayOfWeekField = item.querySelector('[data-frequency-field="day_of_week"]')
        const monthlyDayOptions = item.querySelector('[data-frequency-field="monthly_day_options"]')

        // Hide all conditional fields first
        if (dayOfWeekField) dayOfWeekField.classList.add('hidden')
        if (monthlyDayOptions) monthlyDayOptions.classList.add('hidden')

        // Show appropriate fields based on frequency
        switch (frequency) {
            case 'daily':
                // No additional fields needed
                break
            case 'weekly':
            case 'biweekly':
                // Show day of week
                if (dayOfWeekField) dayOfWeekField.classList.remove('hidden')
                break
            case 'monthly_day':
                // Show ordinal + day of week (e.g., "2nd Friday")
                if (monthlyDayOptions) monthlyDayOptions.classList.remove('hidden')
                break
            case 'monthly_date':
                // No additional fields - uses start date's day number
                break
        }
    }

    itemLocationChanged(event) {
        const item = event.currentTarget.closest(".booking-item")
        const locationId = event.currentTarget.value
        const spaceSelect = item.querySelector('[data-field="space_id"]')

        if (spaceSelect) {
            this.updateSpaceDropdown(spaceSelect, locationId)
        }
    }

    renderExistingRules() {
        this.rules.forEach(rule => {
            if (rule.mode === "recurring") {
                this.addRecurringWithData(rule)
            } else {
                this.addSingleWithData(rule)
            }
        })
    }

    addSingleWithData(data) {
        const template = this.singleEventTemplateTarget
        const clone = template.content.cloneNode(true)
        const item = clone.querySelector(".booking-item")

        item.dataset.bookingIndex = this.bookingIndex++

        // Fill in data
        const locationSelect = clone.querySelector('[data-field="location_id"]')
        const spaceSelect = clone.querySelector('[data-field="space_id"]')
        const startsAtInput = clone.querySelector('[data-field="starts_at"]')
        const durationSelect = clone.querySelector('[data-field="duration"]')
        const notesInput = clone.querySelector('[data-field="notes"]')

        if (locationSelect && data.location_id) locationSelect.value = data.location_id
        if (startsAtInput && data.starts_at) startsAtInput.value = data.starts_at
        if (durationSelect && data.duration) durationSelect.value = data.duration
        if (notesInput && data.notes) notesInput.value = data.notes

        this.bookingsListTarget.appendChild(clone)

        // Populate and select space dropdown after adding to DOM
        if (spaceSelect && data.location_id) {
            this.updateSpaceDropdown(spaceSelect, data.location_id)
            if (data.space_id) {
                spaceSelect.value = data.space_id
            }
        }
    }

    addRecurringWithData(data) {
        const template = this.recurringEventTemplateTarget
        const clone = template.content.cloneNode(true)
        const item = clone.querySelector(".booking-item")

        item.dataset.bookingIndex = this.bookingIndex++

        // Get space select before appending to DOM
        const spaceSelect = clone.querySelector('[data-field="space_id"]')

        // Fill in data
        const fields = {
            location_id: data.location_id,
            frequency: data.frequency,
            day_of_week: data.day_of_week,
            week_ordinal: data.week_ordinal,
            monthly_day_of_week: data.monthly_day_of_week,
            time: data.time,
            start_date: data.start_date,
            end_date: data.end_date,
            duration: data.duration,
            notes: data.notes
        }

        Object.entries(fields).forEach(([field, value]) => {
            if (value) {
                const el = clone.querySelector(`[data-field="${field}"]`)
                if (el) el.value = value
            }
        })

        this.bookingsListTarget.appendChild(clone)

        // Populate and select space dropdown after adding to DOM
        if (spaceSelect && data.location_id) {
            this.updateSpaceDropdown(spaceSelect, data.location_id)
            if (data.space_id) {
                spaceSelect.value = data.space_id
            }
        }

        // Trigger frequency change to show/hide appropriate fields
        const addedItem = this.bookingsListTarget.querySelector(`[data-booking-index="${item.dataset.bookingIndex}"]`)
        if (addedItem) {
            setTimeout(() => {
                this.updateFrequencyFields(addedItem)
            }, 0)
        }
    }

    // ==================== VALIDATION & SUBMISSION ====================

    validateAndSubmit(event) {
        // Check if we have formError target (might not exist in all contexts)
        if (this.hasFormErrorTarget) {
            this.formErrorTarget.classList.add("hidden")
        }

        const mode = this.bookingModeTarget.value

        if (mode === "single") {
            // Validate single mode
            const rules = this.collectSingleModeRules()
            if (!rules) {
                event.preventDefault()
                return false
            }
            this.rulesJsonTarget.value = JSON.stringify(rules)
        } else {
            // Validate multiple mode
            const rules = this.collectMultipleModeRules()
            if (rules === null) {
                // Validation error - missing required fields
                event.preventDefault()
                if (this.hasFormErrorTarget) {
                    this.formErrorTarget.textContent = "Please fill in all required fields."
                    this.formErrorTarget.classList.remove("hidden")
                }
                return false
            }
            // Allow empty rules array for amend flow (user might just be removing)
            this.rulesJsonTarget.value = JSON.stringify(rules)
        }

        return true
    }

    collectSingleModeRules() {
        const locationId = this.singleLocationTarget.value
        const startsAt = this.singleDateTimeTarget.value

        if (!locationId || !startsAt) {
            return null
        }

        return [{
            mode: "single",
            location_id: locationId,
            space_id: this.singleSpaceTarget.value,
            starts_at: startsAt,
            duration: this.singleDurationTarget.value,
            notes: this.singleNotesTarget.value
        }]
    }

    collectMultipleModeRules() {
        const items = this.bookingsListTarget.querySelectorAll(".booking-item")
        const rules = []
        let hasError = false

        items.forEach(item => {
            const type = item.dataset.bookingType
            const locationId = item.querySelector('[data-field="location_id"]')?.value

            if (!locationId) {
                hasError = true
                item.querySelector('[data-field="location_id"]')?.classList.add("border-red-500")
                return
            }

            if (type === "single") {
                const startsAt = item.querySelector('[data-field="starts_at"]')?.value
                if (!startsAt) {
                    hasError = true
                    item.querySelector('[data-field="starts_at"]')?.classList.add("border-red-500")
                    return
                }

                rules.push({
                    mode: "single",
                    location_id: locationId,
                    space_id: item.querySelector('[data-field="space_id"]')?.value || "",
                    starts_at: startsAt,
                    duration: item.querySelector('[data-field="duration"]')?.value || "2",
                    notes: item.querySelector('[data-field="notes"]')?.value || ""
                })
            } else {
                const startDate = item.querySelector('[data-field="start_date"]')?.value
                if (!startDate) {
                    hasError = true
                    item.querySelector('[data-field="start_date"]')?.classList.add("border-red-500")
                    return
                }

                rules.push({
                    mode: "recurring",
                    location_id: locationId,
                    space_id: item.querySelector('[data-field="space_id"]')?.value || "",
                    frequency: item.querySelector('[data-field="frequency"]')?.value || "weekly",
                    day_of_week: item.querySelector('[data-field="day_of_week"]')?.value || "5",
                    week_ordinal: item.querySelector('[data-field="week_ordinal"]')?.value || "1",
                    monthly_day_of_week: item.querySelector('[data-field="monthly_day_of_week"]')?.value || "5",
                    time: item.querySelector('[data-field="time"]')?.value || "19:00",
                    start_date: startDate,
                    end_date: item.querySelector('[data-field="end_date"]')?.value || "",
                    duration: item.querySelector('[data-field="duration"]')?.value || "2",
                    notes: item.querySelector('[data-field="notes"]')?.value || ""
                })
            }
        })

        return hasError ? null : rules
    }

    // ==================== HELPERS ====================

    updateSpaceDropdown(spaceSelect, locationId) {
        if (!spaceSelect) return

        spaceSelect.innerHTML = '<option value="">Entire venue</option>'
        if (!locationId) return

        const location = this.locationsValue.find(l => l.id == locationId)
        if (location && location.spaces) {
            location.spaces.forEach(space => {
                const opt = document.createElement("option")
                opt.value = space.id
                opt.textContent = space.name
                spaceSelect.appendChild(opt)
            })
        }
    }
}
