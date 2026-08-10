import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["inPersonRadio", "onlineRadio", "inPersonFields", "onlineFields", "locationSelect", "spaceFields", "spaceSelect"]
    static values = { spaces: Object }

    toggle() {
        const isOnline = this.onlineRadioTarget.checked

        if (isOnline) {
            this.inPersonFieldsTarget.classList.add("hidden")
            this.onlineFieldsTarget.classList.remove("hidden")
        } else {
            this.inPersonFieldsTarget.classList.remove("hidden")
            this.onlineFieldsTarget.classList.add("hidden")
        }
    }

    locationChanged() {
        this.updateSpaceOptions()
    }

    // Rebuild the space/room dropdown for the currently selected location.
    // Hidden entirely when the location has no spaces defined.
    updateSpaceOptions() {
        if (!this.hasSpaceSelectTarget || !this.hasLocationSelectTarget) return

        const locationId = this.locationSelectTarget.value
        const spaces = (this.spacesValue || {})[locationId] || []
        const select = this.spaceSelectTarget
        const previous = select.value

        select.innerHTML = ""
        const blank = document.createElement("option")
        blank.value = ""
        blank.textContent = "Entire venue"
        select.appendChild(blank)

        spaces.forEach(space => {
            const option = document.createElement("option")
            option.value = space.id
            option.textContent = space.name
            if (String(space.id) === previous) option.selected = true
            select.appendChild(option)
        })

        if (this.hasSpaceFieldsTarget) {
            this.spaceFieldsTarget.classList.toggle("hidden", spaces.length === 0)
        }
    }
}
