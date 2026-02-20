import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["locationSelect", "spaceContainer", "spaceSelect"]

    connect() {
        // Show spaces container if location is already selected
        if (this.locationSelectTarget.value) {
            this.spaceContainerTarget.classList.remove("hidden")
        }
    }

    async loadSpaces() {
        const locationId = this.locationSelectTarget.value

        if (!locationId) {
            this.spaceContainerTarget.classList.add("hidden")
            this.spaceSelectTarget.innerHTML = '<option value="">Select a room...</option>'
            return
        }

        try {
            const response = await fetch(`/manage/locations/${locationId}/spaces.json`)
            const spaces = await response.json()

            // Build options
            let options = '<option value="">Select a room...</option>'
            spaces.forEach(space => {
                options += `<option value="${space.id}">${space.name}</option>`
            })
            this.spaceSelectTarget.innerHTML = options

            // Show the container
            this.spaceContainerTarget.classList.remove("hidden")
        } catch (error) {
            console.error("Error loading spaces:", error)
        }
    }
}
