import { Controller } from "@hotwired/stimulus"

// Controller for showing/hiding minutes field based on opens_unit selection
export default class extends Controller {
    static targets = ["unitSelect", "minutesField"]

    connect() {
        this.updateMinutesVisibility()
    }

    updateMinutesVisibility() {
        const selectedUnit = this.unitSelectTarget.value

        if (selectedUnit === "hours") {
            this.minutesFieldTarget.classList.remove("hidden")
            this.minutesFieldTarget.classList.add("flex")
        } else {
            this.minutesFieldTarget.classList.remove("flex")
            this.minutesFieldTarget.classList.add("hidden")
        }
    }
}
