import { Controller } from "@hotwired/stimulus"

// Controls venue mode selection in ticketing wizard
export default class extends Controller {
    static targets = ["option", "locationPicker", "onlineInfo"]

    select(event) {
        const value = event.target.value

        // Update visual state of options
        this.optionTargets.forEach(option => {
            const optionValue = option.dataset.venueModeValue
            if (optionValue === value) {
                option.classList.remove("border-gray-200", "hover:border-gray-300")
                option.classList.add("border-pink-500", "bg-pink-50")
            } else {
                option.classList.remove("border-pink-500", "bg-pink-50")
                option.classList.add("border-gray-200", "hover:border-gray-300")
            }
        })

        // Show/hide location picker
        if (this.hasLocationPickerTarget) {
            if (value === "org_location") {
                this.locationPickerTarget.classList.remove("hidden")
            } else {
                this.locationPickerTarget.classList.add("hidden")
            }
        }

        // Show/hide online info
        if (this.hasOnlineInfoTarget) {
            if (value === "online") {
                this.onlineInfoTarget.classList.remove("hidden")
            } else {
                this.onlineInfoTarget.classList.add("hidden")
            }
        }
    }
}
