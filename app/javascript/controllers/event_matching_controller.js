import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["container", "option", "input", "eventTypes", "eventTypeChip", "eventTypeInput", "manual"]
    static values = { selected: String }

    connect() {
        this.updateSelection()
    }

    select(event) {
        const option = event.currentTarget
        const value = option.dataset.value

        // Find the hidden input for this option and select it
        const input = this.inputTargets.find(i => i.value === value)
        if (input) {
            input.checked = true
            this.selectedValue = value
            this.updateSelection()
        }
    }

    selectEventType(event) {
        const chip = event.currentTarget
        const value = chip.dataset.value

        // Find the hidden checkbox for this event type and toggle it
        const input = this.eventTypeInputTargets.find(i => i.value === value)
        if (input) {
            input.checked = !input.checked
            this.updateEventTypeChip(chip, input.checked)
        }
    }

    updateEventTypeChip(chip, isSelected) {
        if (isSelected) {
            chip.classList.remove("border-gray-300", "bg-white", "text-gray-700")
            chip.classList.add("border-pink-500", "bg-pink-50", "text-pink-700")
        } else {
            chip.classList.remove("border-pink-500", "bg-pink-50", "text-pink-700")
            chip.classList.add("border-gray-300", "bg-white", "text-gray-700")
        }
    }

    updateSelection() {
        // Update option cards
        this.optionTargets.forEach(option => {
            const value = option.dataset.value
            const isSelected = value === this.selectedValue

            if (isSelected) {
                option.classList.remove("border-gray-200", "bg-gray-50")
                option.classList.add("border-pink-500", "bg-pink-50")
            } else {
                option.classList.remove("border-pink-500", "bg-pink-50")
                option.classList.add("border-gray-200", "bg-gray-50")
            }
        })

        // Show/hide conditional sections
        if (this.hasEventTypesTarget) {
            if (this.selectedValue === "event_types") {
                this.eventTypesTarget.classList.remove("hidden")
            } else {
                this.eventTypesTarget.classList.add("hidden")
            }
        }

        if (this.hasManualTarget) {
            if (this.selectedValue === "manual") {
                this.manualTarget.classList.remove("hidden")
            } else {
                this.manualTarget.classList.add("hidden")
            }
        }
    }

    selectedValueChanged() {
        this.updateSelection()
    }
}
