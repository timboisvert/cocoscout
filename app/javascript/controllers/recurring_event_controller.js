import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["singleFields", "recurringFields", "submitButton", "patternSelect", "customEndDateField", "eventTypeSelect"]

    connect() {
        this.updateButtonText()
    }

    toggle(event) {
        const frequency = event.target.value

        if (frequency === "single") {
            this.singleFieldsTarget.classList.remove("hidden")
            this.recurringFieldsTarget.classList.add("hidden")

            // Enable single fields, disable recurring fields
            this.enableFields(this.singleFieldsTarget)
            this.disableFields(this.recurringFieldsTarget)
        } else {
            this.singleFieldsTarget.classList.add("hidden")
            this.recurringFieldsTarget.classList.remove("hidden")

            // Enable recurring fields, disable single fields
            this.enableFields(this.recurringFieldsTarget)
            this.disableFields(this.singleFieldsTarget)
        }

        this.updateButtonText()
    }

    updateButtonText() {
        if (!this.hasSubmitButtonTarget || !this.hasEventTypeSelectTarget) return

        const eventType = this.eventTypeSelectTarget.value
        const eventTypeLabel = this.eventTypeSelectTarget.options[this.eventTypeSelectTarget.selectedIndex].text

        // Check if recurring is selected
        const frequencySelect = this.element.querySelector('select[name="show[event_frequency]"]')
        const isRecurring = frequencySelect && frequencySelect.value === "recurring"

        let buttonText
        if (isRecurring) {
            // Pluralize the event type
            const plural = this.pluralize(eventTypeLabel)
            buttonText = `Schedule ${plural}`
        } else {
            buttonText = `Schedule ${eventTypeLabel}`
        }

        // Support both <input type="submit"> and <button> elements
        if (this.submitButtonTarget.tagName === 'INPUT') {
            this.submitButtonTarget.value = buttonText
        } else {
            // For <button> elements, find the inner span or set textContent directly
            const span = this.submitButtonTarget.querySelector('span')
            if (span) {
                span.textContent = buttonText
            } else {
                this.submitButtonTarget.textContent = buttonText
            }
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

        const durationType = event.target.value
        if (durationType === "custom") {
            this.customEndDateFieldTarget.classList.remove("hidden")
            this.enableFields(this.customEndDateFieldTarget)
        } else {
            this.customEndDateFieldTarget.classList.add("hidden")
            this.disableFields(this.customEndDateFieldTarget)
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

    enableFields(container) {
        const inputs = container.querySelectorAll("input, select")
        inputs.forEach(input => input.disabled = false)
    }

    disableFields(container) {
        const inputs = container.querySelectorAll("input, select")
        inputs.forEach(input => input.disabled = true)
    }
}