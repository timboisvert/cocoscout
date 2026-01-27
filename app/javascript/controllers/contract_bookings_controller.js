import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "location", "space", "startDateTime", "duration", "notes",
        "singleForm", "recurringForm", "singleOption", "recurringOption",
        "recurringLocation", "recurringSpace", "frequency", "dayOfWeek", "recurringTime",
        "recurringDuration", "startDate", "eventCount", "recurringNotes"
    ]
    static values = { locations: Array }

    connect() {
        // Populate spaces if a location is already selected
        if (this.hasLocationTarget && this.locationTarget.value) {
            this.updateSpaceDropdown(this.spaceTarget, this.locationTarget.value)
        }
        if (this.hasRecurringLocationTarget && this.recurringLocationTarget.value) {
            this.updateSpaceDropdown(this.recurringSpaceTarget, this.recurringLocationTarget.value)
        }
    }

    toggleBookingMode(event) {
        const mode = event.target.value
        if (mode === "single") {
            this.singleFormTarget.classList.remove("hidden")
            this.recurringFormTarget.classList.add("hidden")
            this.singleOptionTarget.classList.remove("border-gray-200", "bg-gray-50")
            this.singleOptionTarget.classList.add("border-pink-500", "bg-pink-50")
            this.recurringOptionTarget.classList.remove("border-pink-500", "bg-pink-50")
            this.recurringOptionTarget.classList.add("border-gray-200", "bg-gray-50")
        } else {
            this.singleFormTarget.classList.add("hidden")
            this.recurringFormTarget.classList.remove("hidden")
            this.recurringOptionTarget.classList.remove("border-gray-200", "bg-gray-50")
            this.recurringOptionTarget.classList.add("border-pink-500", "bg-pink-50")
            this.singleOptionTarget.classList.remove("border-pink-500", "bg-pink-50")
            this.singleOptionTarget.classList.add("border-gray-200", "bg-gray-50")
        }
    }

    locationChanged() {
        const locationId = this.locationTarget.value
        this.updateSpaceDropdown(this.spaceTarget, locationId)
    }

    recurringLocationChanged() {
        const locationId = this.recurringLocationTarget.value
        this.updateSpaceDropdown(this.recurringSpaceTarget, locationId)
    }

    updateSpaceDropdown(spaceSelect, locationId) {
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
