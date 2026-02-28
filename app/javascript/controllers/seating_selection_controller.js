import { Controller } from "@hotwired/stimulus"

// Handles seating configuration selection in the ticketing setup wizard
export default class extends Controller {
    static targets = ["option"]

    select(event) {
        // Update visual state of all options
        this.optionTargets.forEach(option => {
            const isSelected = option.contains(event.target) || option === event.target
            const radio = option.querySelector('input[type="radio"]')

            if (isSelected) {
                option.classList.remove("border-gray-200", "hover:border-gray-300")
                option.classList.add("border-pink-500", "bg-pink-50")
                if (radio) radio.checked = true
            } else {
                option.classList.remove("border-pink-500", "bg-pink-50")
                option.classList.add("border-gray-200", "hover:border-gray-300")
            }
        })
    }
}
