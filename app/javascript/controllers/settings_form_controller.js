import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "form",
        "eventsTab",
        "eventsPanel",
        "singleEventSection",
        "repeatedSection",
        "matchingOption",
        "eventTypesSection",
        "manualEventsSection",
        "slotModeOption",
        "numberedOptions",
        "timeBasedOptions",
        "namedOptions",
        "openListOptions",
        "openListCapacity",
        "scheduleOption",
        "relativeScheduleSection",
        "fixedScheduleSection",
        "scheduledDateSection",
        "unsavedChanges"
    ]

    static values = {
        scope: String,
        eventMatching: String,
        slotMode: String,
        scheduleMode: String
    }

    connect() {
        this.initialFormData = new FormData(this.formTarget)
        this.formTarget.addEventListener("input", () => this.markDirty())
        this.formTarget.addEventListener("change", () => this.markDirty())

        // Initialize slot mode sections - disable inputs in hidden sections
        this.initializeSlotModeSections()
    }

    initializeSlotModeSections() {
        const currentMode = this.slotModeValue
        if (this.hasNumberedOptionsTarget) {
            this.updateSlotModeSection(this.numberedOptionsTarget, currentMode === "numbered")
        }
        if (this.hasTimeBasedOptionsTarget) {
            this.updateSlotModeSection(this.timeBasedOptionsTarget, currentMode === "time_based")
        }
        if (this.hasNamedOptionsTarget) {
            this.updateSlotModeSection(this.namedOptionsTarget, currentMode === "named")
        }
        if (this.hasOpenListOptionsTarget) {
            this.updateSlotModeSection(this.openListOptionsTarget, currentMode === "open_list")
        }
    }

    markDirty() {
        if (this.hasUnsavedChangesTarget) {
            this.unsavedChangesTarget.classList.remove("hidden")
        }
    }

    // ==================== SCOPE ====================
    scopeChanged(event) {
        const scope = event.target.value

        // Show/hide Events tab
        if (this.hasEventsTabTarget) {
            if (scope === "shared_pool") {
                this.eventsTabTarget.classList.add("hidden")
            } else {
                this.eventsTabTarget.classList.remove("hidden")
            }
        }

        // Update event sections
        this.updateEventSections(scope)
    }

    updateEventSections(scope) {
        if (this.hasSingleEventSectionTarget) {
            this.singleEventSectionTarget.classList.toggle("hidden", scope !== "single_event")
        }
        if (this.hasRepeatedSectionTarget) {
            this.repeatedSectionTarget.classList.toggle("hidden", scope !== "repeated")
        }
    }

    // ==================== EVENT MATCHING ====================
    selectEventMatching(event) {
        const value = event.currentTarget.dataset.value

        // Update radio button
        const radio = event.currentTarget.querySelector('input[type="radio"]')
        if (radio) {
            radio.checked = true
        }

        // Update visual state
        this.matchingOptionTargets.forEach(option => {
            const isSelected = option.dataset.value === value
            option.classList.toggle("border-pink-500", isSelected)
            option.classList.toggle("bg-pink-50", isSelected)
            option.classList.toggle("border-gray-200", !isSelected)
            option.classList.toggle("bg-gray-50", !isSelected)
        })

        // Show/hide sections
        if (this.hasEventTypesSectionTarget) {
            this.eventTypesSectionTarget.classList.toggle("hidden", value !== "event_types")
        }
        if (this.hasManualEventsSectionTarget) {
            this.manualEventsSectionTarget.classList.toggle("hidden", value !== "manual")
        }

        this.markDirty()
    }

    toggleEventType(event) {
        const label = event.currentTarget
        const checkbox = label.querySelector('input[type="checkbox"]')

        // Toggle checkbox
        checkbox.checked = !checkbox.checked

        // Update visual state
        if (checkbox.checked) {
            label.classList.remove("border-gray-300", "bg-white", "text-gray-700")
            label.classList.add("border-pink-500", "bg-pink-50", "text-pink-700")
        } else {
            label.classList.remove("border-pink-500", "bg-pink-50", "text-pink-700")
            label.classList.add("border-gray-300", "bg-white", "text-gray-700")
        }

        event.preventDefault()
        this.markDirty()
    }

    toggleManualEvent(event) {
        const label = event.currentTarget
        const checkbox = label.querySelector('input[type="checkbox"]')

        // Toggle checkbox
        checkbox.checked = !checkbox.checked

        // Update visual state
        const indicator = label.querySelector(".rounded-full")
        if (checkbox.checked) {
            label.classList.remove("border-gray-200", "bg-white")
            label.classList.add("border-pink-500", "bg-pink-50")
            indicator.classList.remove("border-2", "border-gray-300")
            indicator.classList.add("bg-pink-500")
            indicator.innerHTML = '<svg class="w-3 h-3 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/></svg>'
        } else {
            label.classList.remove("border-pink-500", "bg-pink-50")
            label.classList.add("border-gray-200", "bg-white")
            indicator.classList.remove("bg-pink-500")
            indicator.classList.add("border-2", "border-gray-300")
            indicator.innerHTML = ''
        }

        event.preventDefault()
        this.markDirty()
    }

    // ==================== SINGLE EVENT SELECTION ====================
    selectSingleEvent(event) {
        const label = event.currentTarget
        const radio = label.querySelector('input[type="radio"]')
        if (radio) {
            radio.checked = true
        }

        // Update visual state for all event options
        const container = label.closest('.space-y-2')
        if (container) {
            container.querySelectorAll('label').forEach(option => {
                const isSelected = option === label
                option.classList.toggle('border-pink-500', isSelected)
                option.classList.toggle('bg-pink-50', isSelected)
                option.classList.toggle('border-gray-200', !isSelected)
                option.classList.toggle('bg-white', !isSelected)

                // Update the indicator circle
                const indicator = option.querySelector('.rounded-full')
                if (indicator) {
                    if (isSelected) {
                        indicator.classList.remove('border-2', 'border-gray-300')
                        indicator.classList.add('bg-pink-500')
                        indicator.innerHTML = '<svg class="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/></svg>'
                    } else {
                        indicator.classList.add('border-2', 'border-gray-300')
                        indicator.classList.remove('bg-pink-500')
                        indicator.innerHTML = ''
                    }
                }
            })
        }

        this.markDirty()
    }

    // ==================== SLOT MODE ====================
    selectSlotMode(event) {
        const value = event.currentTarget.dataset.value

        // Update radio button
        const radio = event.currentTarget.querySelector('input[type="radio"]')
        if (radio) {
            radio.checked = true
        }

        // Update visual state for all slot mode options
        this.slotModeOptionTargets.forEach(option => {
            const isSelected = option.dataset.value === value
            option.classList.toggle("border-pink-500", isSelected)
            option.classList.toggle("bg-pink-50", isSelected)
            option.classList.toggle("border-gray-200", !isSelected)
        })

        // Show/hide option sections and disable inputs in hidden sections
        // This prevents hidden inputs from overriding visible ones on form submit
        if (this.hasNumberedOptionsTarget) {
            this.updateSlotModeSection(this.numberedOptionsTarget, value === "numbered")
        }
        if (this.hasTimeBasedOptionsTarget) {
            this.updateSlotModeSection(this.timeBasedOptionsTarget, value === "time_based")
        }
        if (this.hasNamedOptionsTarget) {
            this.updateSlotModeSection(this.namedOptionsTarget, value === "named")
        }
        if (this.hasOpenListOptionsTarget) {
            this.updateSlotModeSection(this.openListOptionsTarget, value === "open_list")
        }

        this.markDirty()
    }

    updateSlotModeSection(section, isActive) {
        if (!section) return

        section.classList.toggle("hidden", !isActive)

        // Disable/enable all form inputs in this section to prevent hidden fields from being submitted
        const inputs = section.querySelectorAll('input, textarea, select')
        inputs.forEach(input => {
            input.disabled = !isActive
        })
    }

    openListLimitChanged(event) {
        const isLimited = event.target.value === "limited"

        if (this.hasOpenListCapacityTarget) {
            this.openListCapacityTarget.disabled = !isLimited
            if (!isLimited) {
                this.openListCapacityTarget.value = ""
            }
        }

        this.markDirty()
    }

    // ==================== SCHEDULE ====================
    selectScheduleMode(event) {
        const value = event.currentTarget.dataset.value

        // Update radio button
        const radio = event.currentTarget.querySelector('input[type="radio"]')
        if (radio) {
            radio.checked = true
        }

        // Update visual state
        this.scheduleOptionTargets.forEach(option => {
            const isSelected = option.dataset.value === value
            option.classList.toggle("border-pink-500", isSelected)
            option.classList.toggle("bg-pink-50", isSelected)
            option.classList.toggle("border-gray-200", !isSelected)
            option.classList.toggle("bg-gray-50", !isSelected)
        })

        // Show/hide sections
        if (this.hasRelativeScheduleSectionTarget) {
            this.relativeScheduleSectionTarget.classList.toggle("hidden", value !== "relative")
        }
        if (this.hasFixedScheduleSectionTarget) {
            this.fixedScheduleSectionTarget.classList.toggle("hidden", value !== "fixed")
        }

        this.markDirty()
    }

    selectWaitlistMode(event) {
        const value = event.currentTarget.dataset.value

        // Update visual state
        this.scheduleOptionTargets.forEach(option => {
            const isSelected = option.dataset.value === value
            option.classList.toggle("border-pink-500", isSelected)
            option.classList.toggle("bg-pink-50", isSelected)
            option.classList.toggle("border-gray-200", !isSelected)
            option.classList.toggle("bg-gray-50", !isSelected)
        })

        // Show/hide scheduled date section
        if (this.hasScheduledDateSectionTarget) {
            this.scheduledDateSectionTarget.classList.toggle("hidden", value !== "scheduled")

            // Clear opens_at if activating immediately
            if (value === "now") {
                const opensAtInput = this.scheduledDateSectionTarget.querySelector('input[type="datetime-local"]')
                if (opensAtInput) {
                    opensAtInput.value = ""
                }
            }
        }

        this.markDirty()
    }

    // ==================== FORM SUBMISSION ====================
    handleSubmit(event) {
        // For now, just submit normally
        // In the future, we can add confirmation modal here for destructive changes
        // e.g., if slot count is being reduced, show warning
    }
}
