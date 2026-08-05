import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        // Mode selection
        "singleModeBtn", "multipleModeBtn", "singleModeContent", "multipleModeContent",
        "bookingMode", "rulesJson",
        // Single mode fields
        "singleLocation", "singleSpace", "singleDateTime", "singleDuration", "singleNotes",
        "singleEventType",
        "singleEventTimeToggle", "singleEventTimeRow", "singleEventTime", "singleEventEndTime",
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

        // Carry a filled-in single event over as the first booking, so switching
        // to multiple never throws away what you already entered — a single
        // event is just the first item in a multi-event list. Only when the
        // list is empty, so we never duplicate on repeated toggles.
        if (this.bookingsListTarget.children.length === 0) {
            const single = this.collectSingleModeRules()
            if (single && single.length) {
                this.addSingleWithData(single[0])
            }
        }
    }

    // ==================== SINGLE MODE ====================

    singleLocationChanged() {
        this.updateSpaceDropdown(this.singleSpaceTarget, this.singleLocationTarget.value)
    }

    toggleSingleEventTime() {
        const isChecked = this.singleEventTimeToggleTarget.checked
        if (isChecked) {
            this.singleEventTimeRowTarget.classList.remove("hidden")

            // Set min/max constraints based on rental period
            const rentalStart = this.singleDateTimeTarget.value
            if (rentalStart) {
                const startDate = new Date(rentalStart)
                const duration = parseFloat(this.singleDurationTarget.value) || 2
                const endDate = new Date(startDate.getTime() + duration * 60 * 60 * 1000)
                const rentalEnd = this.formatDateTimeLocal(endDate)

                this.singleEventTimeTarget.min = rentalStart
                this.singleEventTimeTarget.max = rentalEnd
                this.singleEventEndTimeTarget.min = rentalStart
                this.singleEventEndTimeTarget.max = rentalEnd

                // Default to same times as rental if not set
                if (!this.singleEventTimeTarget.value) {
                    this.singleEventTimeTarget.value = rentalStart
                }
                if (!this.singleEventEndTimeTarget.value) {
                    this.singleEventEndTimeTarget.value = rentalEnd
                }
            }
        } else {
            this.singleEventTimeRowTarget.classList.add("hidden")
            this.singleEventTimeTarget.value = ""
            this.singleEventEndTimeTarget.value = ""
        }
    }

    formatDateTimeLocal(date) {
        const year = date.getFullYear()
        const month = String(date.getMonth() + 1).padStart(2, '0')
        const day = String(date.getDate()).padStart(2, '0')
        const hours = String(date.getHours()).padStart(2, '0')
        const minutes = String(date.getMinutes()).padStart(2, '0')
        return `${year}-${month}-${day}T${hours}:${minutes}`
    }

    // ==================== MULTIPLE MODE ====================

    addSingleEvent() {
        const template = this.singleEventTemplateTarget
        const clone = template.content.cloneNode(true)
        const item = clone.querySelector(".booking-item")

        item.dataset.bookingIndex = this.bookingIndex++

        const locationSelect = clone.querySelector('[data-field="location_id"]')
        const spaceSelect = clone.querySelector('[data-field="space_id"]')
        const startsAtInput = clone.querySelector('[data-field="starts_at"]')
        const durationSelect = clone.querySelector('[data-field="duration"]')

        // Inherit from whatever the user just set up: the last single event if
        // there is one, else the last recurring series (same room, same setup —
        // only the date is theirs to pick).
        const lastSingle = this.lastItemOfType("single")
        const lastRecurring = this.lastItemOfType("recurring")
        const source = lastSingle || lastRecurring

        if (source) {
            this.copySharedFields(source, clone)

            const lastDuration = source.querySelector('[data-field="duration"]')?.value
            if (durationSelect && lastDuration) {
                this.setDurationField(durationSelect, lastDuration)
            }

            if (startsAtInput) {
                const lastStartsAt = lastSingle?.querySelector('[data-field="starts_at"]')?.value
                if (lastStartsAt) {
                    // From a single event: same time, next day.
                    const lastDate = new Date(lastStartsAt)
                    if (!isNaN(lastDate.getTime())) {
                        lastDate.setDate(lastDate.getDate() + 1)
                        startsAtInput.value = this.formatDateTimeLocal(lastDate)
                    }
                } else {
                    // From a recurring series: no single date to advance — the
                    // date is the user's to pick, but the moment they pick one
                    // the series' start time fills in (unless they typed a time).
                    const time = lastRecurring?.querySelector('[data-field="time"]')?.value
                    if (time) {
                        startsAtInput.addEventListener("change", () => {
                            if (startsAtInput.value && startsAtInput.value.endsWith("T00:00")) {
                                startsAtInput.value = `${startsAtInput.value.split("T")[0]}T${time}`
                            }
                        }, { once: true })
                    }
                }
            }
        } else {
            // No previous event — use default location
            if (locationSelect && this.defaultLocationIdValue) {
                locationSelect.value = this.defaultLocationIdValue
                if (spaceSelect) {
                    this.updateSpaceDropdown(spaceSelect, this.defaultLocationIdValue)
                }
            }
        }

        this.bookingsListTarget.appendChild(clone)

        // Focus the date/time input so user can adjust
        const dateTimeInput = this.bookingsListTarget.lastElementChild.querySelector('[data-field="starts_at"]')
        if (dateTimeInput) dateTimeInput.focus()
    }

    addRecurringSeries() {
        const template = this.recurringEventTemplateTarget
        const clone = template.content.cloneNode(true)
        const item = clone.querySelector(".booking-item")

        item.dataset.bookingIndex = this.bookingIndex++

        // Inherit the previous rule's setup: same room, same cadence (weekly
        // stays weekly on the same day), same time and duration. Only the
        // date range is left for the user to choose.
        const lastRecurring = this.lastItemOfType("recurring")
        const lastSingle = this.lastItemOfType("single")

        if (lastRecurring) {
            this.copySharedFields(lastRecurring, clone)

            for (const field of ["frequency", "day_of_week", "week_ordinal", "monthly_day_of_week", "time"]) {
                const from = lastRecurring.querySelector(`[data-field="${field}"]`)
                const to = clone.querySelector(`[data-field="${field}"]`)
                if (from && to && from.value) to.value = from.value
            }
            const lastDuration = lastRecurring.querySelector('[data-field="duration"]')?.value
            const durationSelect = clone.querySelector('[data-field="duration"]')
            if (durationSelect && lastDuration) this.setDurationField(durationSelect, lastDuration)

            // The template prefills a date range; an inherited rule shouldn't
            // presume dates — that's the one thing the user came to change.
            const startDate = clone.querySelector('[data-field="start_date"]')
            const endDate = clone.querySelector('[data-field="end_date"]')
            if (startDate) startDate.value = ""
            if (endDate) endDate.value = ""

            this.updateFrequencyFields(item)
        } else if (lastSingle) {
            // Coming from a single event: same room and duration, weekly on
            // that event's weekday at its time.
            this.copySharedFields(lastSingle, clone)

            const lastDuration = lastSingle.querySelector('[data-field="duration"]')?.value
            const durationSelect = clone.querySelector('[data-field="duration"]')
            if (durationSelect && lastDuration) this.setDurationField(durationSelect, lastDuration)

            const startsAt = lastSingle.querySelector('[data-field="starts_at"]')?.value
            if (startsAt) {
                const date = new Date(startsAt)
                if (!isNaN(date.getTime())) {
                    const freq = clone.querySelector('[data-field="frequency"]')
                    const dow = clone.querySelector('[data-field="day_of_week"]')
                    const time = clone.querySelector('[data-field="time"]')
                    if (freq) freq.value = "weekly"
                    if (dow) dow.value = String(date.getDay())
                    if (time) time.value = `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`
                }
            }
            this.updateFrequencyFields(item)
        } else if (this.defaultLocationIdValue) {
            const locationSelect = clone.querySelector('[data-field="location_id"]')
            const spaceSelect = clone.querySelector('[data-field="space_id"]')
            if (locationSelect) {
                locationSelect.value = this.defaultLocationIdValue
                if (spaceSelect) this.updateSpaceDropdown(spaceSelect, this.defaultLocationIdValue)
            }
        }

        this.bookingsListTarget.appendChild(clone)

        // Focus the start date input — everything else is pre-filled.
        const startDateInput = this.bookingsListTarget.lastElementChild.querySelector('[data-field="start_date"]')
        if (startDateInput) startDateInput.focus()
    }

    // The most recent rule of a type ("single" | "recurring"), or null.
    lastItemOfType(type) {
        const items = this.bookingsListTarget.querySelectorAll(`.booking-item[data-booking-type="${type}"]`)
        return items.length > 0 ? items[items.length - 1] : null
    }

    // Fields every rule shape shares: the room and the event type.
    copySharedFields(source, clone) {
        const locationId = source.querySelector('[data-field="location_id"]')?.value
        const spaceId = source.querySelector('[data-field="space_id"]')?.value
        const eventType = source.querySelector('[data-field="event_type"]')?.value

        const locationSelect = clone.querySelector('[data-field="location_id"]')
        const spaceSelect = clone.querySelector('[data-field="space_id"]')
        const eventTypeSelect = clone.querySelector('[data-field="event_type"]')

        if (locationSelect && locationId) {
            locationSelect.value = locationId
            if (spaceSelect) {
                this.updateSpaceDropdown(spaceSelect, locationId)
                if (spaceId) spaceSelect.value = spaceId
            }
        }
        if (eventTypeSelect && eventType) eventTypeSelect.value = eventType
    }

    removeBooking(event) {
        const item = event.currentTarget.closest(".booking-item")
        if (item) {
            item.remove()
        }
    }

    frequencyChanged(event) {
        this.updateFrequencyFields(event.currentTarget.closest(".booking-item"))
    }

    // Show/hide the conditional frequency sub-fields (day-of-week for weekly/biweekly,
    // the week+day pickers for monthly "same day") to match an item's current
    // frequency <select>. Runs both on change AND when a saved booking is restored,
    // so returning to this step shows the right fields for the saved frequency
    // without forcing a re-pick. (This was already called on restore — line in
    // addRecurringWithData — but was never defined, so restored recurring bookings
    // kept their sub-fields hidden until you re-selected the frequency.)
    updateFrequencyFields(item) {
        if (!item) return

        const frequency = item.querySelector('[data-field="frequency"]')?.value
        const dayOfWeekField = item.querySelector('[data-frequency-field="day_of_week"]')
        const monthlyDayOptions = item.querySelector('[data-frequency-field="monthly_day_options"]')

        // Hide all conditional fields first, then reveal the ones this frequency needs.
        if (dayOfWeekField) dayOfWeekField.classList.add('hidden')
        if (monthlyDayOptions) monthlyDayOptions.classList.add('hidden')

        switch (frequency) {
            case 'weekly':
            case 'biweekly':
                if (dayOfWeekField) dayOfWeekField.classList.remove('hidden')
                break
            case 'monthly_day':
                if (monthlyDayOptions) monthlyDayOptions.classList.remove('hidden')
                break
            // 'daily' and 'monthly_date' need no extra fields.
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

    toggleItemEventTime(event) {
        const item = event.currentTarget.closest(".booking-item") || event.currentTarget.closest("[data-create-event-options]")
            ? event.currentTarget.closest(".booking-item") : null
        // For single mode, just use the parent container
        const container = event.currentTarget.closest("[data-create-event-options]") || event.currentTarget.closest(".booking-item")
        const eventTimeRow = container?.querySelector('[data-event-time-row]')
        const isChecked = event.currentTarget.checked

        if (eventTimeRow) {
            if (isChecked) {
                eventTimeRow.classList.remove("hidden")
                // For single events in multiple mode, default to same times as rental
                const bookingItem = event.currentTarget.closest(".booking-item")
                if (bookingItem && bookingItem.dataset.bookingType === "single") {
                    const eventStartsAtInput = bookingItem.querySelector('[data-field="event_starts_at"]')
                    const eventEndsAtInput = bookingItem.querySelector('[data-field="event_ends_at"]')
                    const startsAtInput = bookingItem.querySelector('[data-field="starts_at"]')
                    const durationSelect = bookingItem.querySelector('[data-field="duration"]')

                    if (startsAtInput?.value) {
                        const startDate = new Date(startsAtInput.value)
                        const duration = parseFloat(durationSelect?.value) || 2
                        const endDate = new Date(startDate.getTime() + duration * 60 * 60 * 1000)
                        const rentalEnd = this.formatDateTimeLocal(endDate)

                        // Set min/max constraints
                        if (eventStartsAtInput) {
                            eventStartsAtInput.min = startsAtInput.value
                            eventStartsAtInput.max = rentalEnd
                            if (!eventStartsAtInput.value) eventStartsAtInput.value = startsAtInput.value
                        }
                        if (eventEndsAtInput) {
                            eventEndsAtInput.min = startsAtInput.value
                            eventEndsAtInput.max = rentalEnd
                            if (!eventEndsAtInput.value) eventEndsAtInput.value = rentalEnd
                        }
                    }
                } else if (bookingItem && bookingItem.dataset.bookingType === "recurring") {
                    // For recurring events, default to same time as rental time
                    const eventTimeInput = bookingItem.querySelector('[data-field="event_time"]')
                    const eventEndTimeInput = bookingItem.querySelector('[data-field="event_end_time"]')
                    const timeInput = bookingItem.querySelector('[data-field="time"]')
                    const durationSelect = bookingItem.querySelector('[data-field="duration"]')

                    if (timeInput?.value) {
                        const [hours, minutes] = timeInput.value.split(':').map(Number)
                        const duration = parseFloat(durationSelect?.value) || 2
                        const endHours = hours + Math.floor(duration)
                        const endMinutes = minutes + Math.round((duration % 1) * 60)
                        const adjustedHours = (endHours + Math.floor(endMinutes / 60)) % 24
                        const adjustedMinutes = endMinutes % 60
                        const rentalEndTime = `${String(adjustedHours).padStart(2, '0')}:${String(adjustedMinutes).padStart(2, '0')}`

                        // Set min/max constraints (time inputs)
                        if (eventTimeInput) {
                            eventTimeInput.min = timeInput.value
                            eventTimeInput.max = rentalEndTime
                            if (!eventTimeInput.value) eventTimeInput.value = timeInput.value
                        }
                        if (eventEndTimeInput) {
                            eventEndTimeInput.min = timeInput.value
                            eventEndTimeInput.max = rentalEndTime
                            if (!eventEndTimeInput.value) eventEndTimeInput.value = rentalEndTime
                        }
                    }
                }
            } else {
                eventTimeRow.classList.add("hidden")
            }
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
        if (durationSelect && data.duration) this.setDurationField(durationSelect, data.duration)
        if (notesInput && data.notes) notesInput.value = data.notes

        this.bookingsListTarget.appendChild(clone)

        // Populate and select space dropdown after adding to DOM
        if (spaceSelect && data.location_id) {
            this.updateSpaceDropdown(spaceSelect, data.location_id)
            if (data.space_id) {
                spaceSelect.value = data.space_id
            }
        }

        // Restore event type and event time toggle state
        const addedItem = this.bookingsListTarget.lastElementChild
        if (addedItem) {
            // Restore event type
            const eventTypeSelect = addedItem.querySelector('[data-field="event_type"]')
            if (eventTypeSelect && data.event_type) eventTypeSelect.value = data.event_type

            // Restore event time toggle state
            if (data.event_starts_at || data.event_ends_at) {
                const eventTimeToggle = addedItem.querySelector('[data-field="event_time_toggle"]')
                const eventTimeRow = addedItem.querySelector('[data-event-time-row]')
                const eventStartsAtInput = addedItem.querySelector('[data-field="event_starts_at"]')
                const eventEndsAtInput = addedItem.querySelector('[data-field="event_ends_at"]')

                if (eventTimeToggle) eventTimeToggle.checked = true
                if (eventTimeRow) eventTimeRow.classList.remove("hidden")
                if (eventStartsAtInput && data.event_starts_at) eventStartsAtInput.value = data.event_starts_at
                if (eventEndsAtInput && data.event_ends_at) eventEndsAtInput.value = data.event_ends_at
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

        // Show the right sub-fields for the restored frequency. The frequency
        // value is already set above, so this can run synchronously.
        const addedItem = this.bookingsListTarget.querySelector(`[data-booking-index="${item.dataset.bookingIndex}"]`)
        if (addedItem) {
            this.updateFrequencyFields(addedItem)

            // Restore event type
            const eventTypeSelect = addedItem.querySelector('[data-field="event_type"]')
            if (eventTypeSelect && data.event_type) eventTypeSelect.value = data.event_type

            // Restore event time toggle state
            if (data.event_time || data.event_end_time) {
                const eventTimeToggle = addedItem.querySelector('[data-field="event_time_toggle"]')
                const eventTimeRow = addedItem.querySelector('[data-event-time-row]')
                const eventTimeInput = addedItem.querySelector('[data-field="event_time"]')
                const eventEndTimeInput = addedItem.querySelector('[data-field="event_end_time"]')

                if (eventTimeToggle) eventTimeToggle.checked = true
                if (eventTimeRow) eventTimeRow.classList.remove("hidden")
                if (eventTimeInput && data.event_time) eventTimeInput.value = data.event_time
                if (eventEndTimeInput && data.event_end_time) eventEndTimeInput.value = data.event_end_time
            }
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

        const rule = {
            mode: "single",
            location_id: locationId,
            space_id: this.singleSpaceTarget.value,
            starts_at: startsAt,
            duration: this.singleDurationTarget.value,
            notes: this.singleNotesTarget.value
        }

        // Include event_type
        if (this.hasSingleEventTypeTarget) {
            rule.event_type = this.singleEventTypeTarget.value
        }

        // Include event_starts_at if toggle is checked and value exists
        if (this.hasSingleEventTimeToggleTarget && this.singleEventTimeToggleTarget.checked) {
            const eventStartsAt = this.singleEventTimeTarget.value
            if (eventStartsAt) {
                rule.event_starts_at = eventStartsAt
            }
            const eventEndsAt = this.singleEventEndTimeTarget.value
            if (eventEndsAt) {
                rule.event_ends_at = eventEndsAt
            }
        }

        return [rule]
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

                const singleRule = {
                    mode: "single",
                    location_id: locationId,
                    space_id: item.querySelector('[data-field="space_id"]')?.value || "",
                    starts_at: startsAt,
                    duration: item.querySelector('[data-field="duration"]')?.value || "2",
                    notes: item.querySelector('[data-field="notes"]')?.value || ""
                }

                // Include event_type
                const eventTypeSelect = item.querySelector('[data-field="event_type"]')
                if (eventTypeSelect) singleRule.event_type = eventTypeSelect.value

                // Include event_starts_at if toggle is checked
                const eventTimeToggle = item.querySelector('[data-field="event_time_toggle"]')
                if (eventTimeToggle?.checked) {
                    const eventStartsAt = item.querySelector('[data-field="event_starts_at"]')?.value
                    if (eventStartsAt) {
                        singleRule.event_starts_at = eventStartsAt
                    }
                    const eventEndsAt = item.querySelector('[data-field="event_ends_at"]')?.value
                    if (eventEndsAt) {
                        singleRule.event_ends_at = eventEndsAt
                    }
                }

                rules.push(singleRule)
            } else {
                const startDate = item.querySelector('[data-field="start_date"]')?.value
                if (!startDate) {
                    hasError = true
                    item.querySelector('[data-field="start_date"]')?.classList.add("border-red-500")
                    return
                }

                const recurringRule = {
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
                }

                // Include event_type
                const eventTypeSelect = item.querySelector('[data-field="event_type"]')
                if (eventTypeSelect) recurringRule.event_type = eventTypeSelect.value

                // Include event_time if toggle is checked
                const eventTimeToggle = item.querySelector('[data-field="event_time_toggle"]')
                if (eventTimeToggle?.checked) {
                    const eventTime = item.querySelector('[data-field="event_time"]')?.value
                    if (eventTime) {
                        recurringRule.event_time = eventTime
                    }
                    const eventEndTime = item.querySelector('[data-field="event_end_time"]')?.value
                    if (eventEndTime) {
                        recurringRule.event_end_time = eventEndTime
                    }
                }

                rules.push(recurringRule)
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

    // Sets a duration_field component (decimal-hours unit) from an hours value,
    // updating both the hidden field and the hours/minutes selects.
    setDurationField(hiddenInput, hoursValue) {
        if (!hiddenInput) return
        const v = parseFloat(hoursValue)
        if (isNaN(v)) return
        hiddenInput.value = hoursValue
        const wrapper = hiddenInput.closest('[data-controller~="duration-field"]')
        if (!wrapper) return
        const hoursSelect = wrapper.querySelector('[data-duration-field-target="hours"]')
        const minutesSelect = wrapper.querySelector('[data-duration-field-target="minutes"]')
        if (hoursSelect) hoursSelect.value = Math.floor(v)
        if (minutesSelect) minutesSelect.value = Math.round((v % 1) * 60)
    }
}
