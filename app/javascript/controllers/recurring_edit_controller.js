import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["singleFields", "recurringFields", "editScopeThis", "editScopeAll", "customEndDateField", "patternSelect", "startDatetime", "submitButton", "eventTypeSelect"]

    connect() {
        this.toggleFields()
        // Initialize pattern options with the current start datetime value
        this.initializePatternOptions()
        // Initialize button text
        this.updateButtonText()
    }

    initializePatternOptions() {
        if (!this.hasStartDatetimeTarget || !this.hasPatternSelectTarget) return

        const dateValue = this.startDatetimeTarget.value
        if (dateValue) {
            this.generatePatternOptions(dateValue)
        }
    }

    toggleFields() {
        if (!this.hasEditScopeAllTarget) return

        const editScopeAll = this.editScopeAllTarget.checked

        if (editScopeAll) {
            this.singleFieldsTarget.classList.add("hidden")
            this.recurringFieldsTarget.classList.remove("hidden")
        } else {
            this.singleFieldsTarget.classList.remove("hidden")
            this.recurringFieldsTarget.classList.add("hidden")
        }

        // Update button text when toggling between single and all
        this.updateButtonText()
    }

    updateButtonText() {
        if (!this.hasSubmitButtonTarget || !this.hasEventTypeSelectTarget) return

        const eventType = this.eventTypeSelectTarget.value
        const eventTypeLabel = this.eventTypeSelectTarget.options[this.eventTypeSelectTarget.selectedIndex].text

        // Check if editing all occurrences
        const editingAll = this.hasEditScopeAllTarget && this.editScopeAllTarget.checked

        if (editingAll) {
            // Pluralize the event type
            const plural = this.pluralize(eventTypeLabel)
            this.submitButtonTarget.value = `Update ${plural}`
        } else {
            this.submitButtonTarget.value = `Update ${eventTypeLabel}`
        }
    }

    pluralize(word) {
        // Simple pluralization rules
        if (word === "Show") return "Shows"
        if (word === "Rehearsal") return "Rehearsals"
        if (word === "Meeting") return "Meetings"
        return word + "s"
    }

    updatePatternOptions(event) {
        const dateValue = event.target.value
        if (!dateValue || !this.hasPatternSelectTarget) return

        this.generatePatternOptions(dateValue)
    }

    generatePatternOptions(dateValue) {
        const date = new Date(dateValue)
        const dayName = date.toLocaleDateString('en-US', { weekday: 'long' })
        const dayNamePlural = dayName + 's'
        const dateOfMonth = date.getDate()

        // Calculate which week of the month this date falls on
        const weekOfMonth = Math.ceil(dateOfMonth / 7)
        const weekOrdinal = this.getWeekOrdinal(weekOfMonth)

        // Generate ordinal suffix (1st, 2nd, 3rd, etc.)
        const ordinal = this.getOrdinal(dateOfMonth)

        // Clear existing options
        this.patternSelectTarget.innerHTML = ''

        // Add blank option
        const blankOption = document.createElement('option')
        blankOption.value = ''
        blankOption.textContent = 'Select pattern'
        this.patternSelectTarget.appendChild(blankOption)

        // Add pattern options
        const patterns = [
            { label: `Weekly on ${dayNamePlural}`, value: 'weekly' },
            { label: `Every other ${dayName}`, value: 'biweekly' },
            { label: `Monthly on the ${ordinal}`, value: 'monthly_date' },
            { label: `Monthly on the ${weekOrdinal} ${dayName}`, value: 'monthly_week' }
        ]

        patterns.forEach(pattern => {
            const option = document.createElement('option')
            option.value = pattern.value
            option.textContent = pattern.label
            this.patternSelectTarget.appendChild(option)
        })
    }

    toggleCustomEndDate(event) {
        if (!this.hasCustomEndDateFieldTarget) return

        const selectedValue = event.target.value
        if (selectedValue === "custom") {
            this.customEndDateFieldTarget.classList.remove("hidden")
        } else {
            this.customEndDateFieldTarget.classList.add("hidden")
        }
    }

    getWeekOrdinal(n) {
        const words = ["first", "second", "third", "fourth", "fifth"]
        return words[n - 1] || `${n}th`
    }

    getOrdinal(n) {
        const s = ["th", "st", "nd", "rd"]
        const v = n % 100
        return n + (s[(v - 20) % 10] || s[v] || s[0])
    }
}
