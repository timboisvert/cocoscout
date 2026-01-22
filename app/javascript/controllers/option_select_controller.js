import { Controller } from "@hotwired/stimulus"

// Generic controller for click-to-select option cards (no visible radio buttons)
export default class extends Controller {
    static targets = ["option", "input", "conditionalRelative", "conditionalFixed", "conditionalScheduled", "conditionalImmediate", "conditionalManual"]
    static values = { selected: String }

    connect() {
        this.updateSelection()
    }

    select(event) {
        const option = event.currentTarget.closest("[data-option-select-target='option']") || event.currentTarget
        const value = option.dataset.value

        // Find the hidden input for this option and select it
        const input = this.inputTargets.find(i => i.value === value)
        if (input) {
            input.checked = true
            this.selectedValue = value
            this.updateSelection()
        }
    }

    updateSelection() {
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

        // Handle conditional sections for schedule page
        if (this.hasConditionalRelativeTarget) {
            if (this.selectedValue === "relative") {
                this.conditionalRelativeTarget.classList.remove("hidden")
            } else {
                this.conditionalRelativeTarget.classList.add("hidden")
            }
        }

        if (this.hasConditionalFixedTarget) {
            if (this.selectedValue === "fixed") {
                this.conditionalFixedTarget.classList.remove("hidden")
            } else {
                this.conditionalFixedTarget.classList.add("hidden")
            }
        }

        // Handle waitlist scheduled section
        if (this.hasConditionalScheduledTarget) {
            if (this.selectedValue === "scheduled") {
                this.conditionalScheduledTarget.classList.remove("hidden")
            } else {
                this.conditionalScheduledTarget.classList.add("hidden")
            }
        }

        // Handle immediate schedule section
        if (this.hasConditionalImmediateTarget) {
            if (this.selectedValue === "immediate") {
                this.conditionalImmediateTarget.classList.remove("hidden")
            } else {
                this.conditionalImmediateTarget.classList.add("hidden")
            }
        }

        // Handle manual selection section
        if (this.hasConditionalManualTarget) {
            if (this.selectedValue === "manual") {
                this.conditionalManualTarget.classList.remove("hidden")
            } else {
                this.conditionalManualTarget.classList.add("hidden")
            }
        }
    }

    selectedValueChanged() {
        this.updateSelection()
    }
}
