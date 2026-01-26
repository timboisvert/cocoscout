import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "location", "space", "startDateTime", "duration", "notes", "list", "bookingsJson",
        "singleForm", "recurringForm", "singleOption", "recurringOption",
        "recurringLocation", "recurringSpace", "frequency", "dayOfWeek", "recurringTime",
        "recurringDuration", "startDate", "eventCount", "recurringNotes",
        "spacesModal", "spacesContent"
    ]
    static values = { existing: Array, locations: Array }

    connect() {
        this.bookings = this.existingValue || []
        this.renderList()
    }

    toggleBookingType(event) {
        const type = event.target.value
        if (type === "single") {
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
        spaceSelect.innerHTML = '<option value="">Entire venue / no specific space</option>'

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

    addBooking() {
        const locationId = this.locationTarget.value
        const spaceId = this.spaceTarget.value
        const startDateTime = this.startDateTimeTarget.value
        const duration = parseFloat(this.durationTarget.value)
        const notes = this.notesTarget.value

        if (!locationId || !startDateTime) {
            alert("Please select a location and date/time")
            return
        }

        const startDate = new Date(startDateTime)
        const endDate = new Date(startDate.getTime() + duration * 60 * 60 * 1000)

        const locationName = this.locationTarget.options[this.locationTarget.selectedIndex]?.textContent
        const spaceName = spaceId ? this.spaceTarget.options[this.spaceTarget.selectedIndex]?.textContent : "Entire venue"

        this.bookings.push({
            location_id: parseInt(locationId),
            location_space_id: spaceId ? parseInt(spaceId) : null,
            starts_at: startDateTime,
            ends_at: this.formatDateTime(endDate),
            notes: notes,
            display_name: `${locationName}${spaceId ? ` - ${spaceName}` : ""}`,
            display_date: this.formatDisplayDate(startDate),
            display_time: `${this.formatTime(startDate)} - ${this.formatTime(endDate)} (${duration}h)`
        })

        this.renderList()
        this.clearSingleForm()
        this.updateHiddenField()
    }

    addRecurringBookings() {
        const locationId = this.recurringLocationTarget.value
        const spaceId = this.recurringSpaceTarget.value
        const frequency = this.frequencyTarget.value
        const dayOfWeek = parseInt(this.dayOfWeekTarget.value)
        const time = this.recurringTimeTarget.value
        const duration = parseFloat(this.recurringDurationTarget.value)
        const startDate = new Date(this.startDateTarget.value)
        const count = parseInt(this.eventCountTarget.value)
        const notes = this.recurringNotesTarget.value

        if (!locationId || !time) {
            alert("Please select a location and time")
            return
        }

        const locationName = this.recurringLocationTarget.options[this.recurringLocationTarget.selectedIndex]?.textContent
        const spaceName = spaceId ? this.recurringSpaceTarget.options[this.recurringSpaceTarget.selectedIndex]?.textContent : "Entire venue"

        // Find the first occurrence of the selected day of week
        let currentDate = new Date(startDate)
        while (currentDate.getDay() !== dayOfWeek) {
            currentDate.setDate(currentDate.getDate() + 1)
        }

        // Generate recurring bookings
        let generated = 0
        while (generated < count) {
            const [hours, minutes] = time.split(":").map(Number)
            const eventStart = new Date(currentDate)
            eventStart.setHours(hours, minutes, 0, 0)

            const eventEnd = new Date(eventStart.getTime() + duration * 60 * 60 * 1000)

            this.bookings.push({
                location_id: parseInt(locationId),
                location_space_id: spaceId ? parseInt(spaceId) : null,
                starts_at: this.formatDateTime(eventStart),
                ends_at: this.formatDateTime(eventEnd),
                notes: notes,
                display_name: `${locationName}${spaceId ? ` - ${spaceName}` : ""}`,
                display_date: this.formatDisplayDate(eventStart),
                display_time: `${this.formatTime(eventStart)} - ${this.formatTime(eventEnd)} (${duration}h)`
            })

            generated++

            // Advance to next occurrence
            switch (frequency) {
                case "weekly":
                    currentDate.setDate(currentDate.getDate() + 7)
                    break
                case "biweekly":
                    currentDate.setDate(currentDate.getDate() + 14)
                    break
                case "monthly":
                    currentDate.setMonth(currentDate.getMonth() + 1)
                    break
            }
        }

        this.renderList()
        this.updateHiddenField()

        alert(`Generated ${count} recurring bookings`)
    }

    removeBooking(event) {
        const index = parseInt(event.currentTarget.dataset.index)
        this.bookings.splice(index, 1)
        this.renderList()
        this.updateHiddenField()
    }

    clearSingleForm() {
        this.startDateTimeTarget.value = ""
        this.notesTarget.value = ""
        this.durationTarget.value = "2"
    }

    formatDateTime(date) {
        const pad = n => n.toString().padStart(2, "0")
        return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`
    }

    formatDisplayDate(date) {
        return date.toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric", year: "numeric" })
    }

    formatTime(date) {
        return date.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit", hour12: true })
    }

    renderList() {
        if (this.bookings.length === 0) {
            this.listTarget.innerHTML = '<p class="text-gray-500 text-sm text-center py-4">No bookings added yet.</p>'
            return
        }

        this.listTarget.innerHTML = this.bookings.map((booking, index) => `
      <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg border border-gray-200">
        <div>
          <div class="font-medium text-gray-900">${booking.display_name || `Location ${booking.location_id}`}</div>
          <div class="text-sm text-gray-500">
            ${booking.display_date || booking.starts_at.split('T')[0]} • ${booking.display_time || ''}
            ${booking.notes ? `<span class="text-gray-400">— ${booking.notes}</span>` : ''}
          </div>
        </div>
        <button type="button" data-action="click->contract-bookings#removeBooking" data-index="${index}" class="text-pink-500 hover:text-pink-700">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>
    `).join("")
    }

    updateHiddenField() {
        this.bookingsJsonTarget.value = JSON.stringify(this.bookings)
    }

    // Modal management
    openSpacesModal(event) {
        event.preventDefault()
        this.spacesModalTarget.classList.remove("hidden")
        document.body.classList.add("overflow-hidden")

        // Check if a location is selected
        const locationId = this.locationTarget.value || this.recurringLocationTarget.value
        if (locationId) {
            this.loadSpacesForLocation(locationId)
        } else {
            this.spacesContentTarget.innerHTML = '<p class="text-sm text-gray-600">Select a location first, then come back here to manage its spaces.</p>'
        }
    }

    closeSpacesModal() {
        this.spacesModalTarget.classList.add("hidden")
        document.body.classList.remove("overflow-hidden")

        // Refresh the space dropdowns with potentially new data
        const locationId = this.locationTarget.value
        if (locationId) {
            this.refreshSpacesFromServer(locationId)
        }
    }

    loadSpacesForLocation(locationId) {
        const location = this.locationsValue.find(l => l.id == locationId)
        if (!location) return

        let html = `
      <div class="mb-4">
        <p class="text-sm text-gray-600 mb-2">Spaces at <strong>${location.name}</strong>:</p>
      </div>
    `

        if (location.spaces.length === 0) {
            html += '<p class="text-sm text-gray-500 italic">No spaces defined for this location.</p>'
        } else {
            html += '<ul class="space-y-2">'
            location.spaces.forEach(space => {
                html += `
          <li class="flex items-center justify-between p-2 bg-gray-50 rounded">
            <span class="text-sm text-gray-900">${space.name}</span>
          </li>
        `
            })
            html += '</ul>'
        }

        html += `
      <div class="mt-4 pt-4 border-t border-gray-200">
        <p class="text-sm text-gray-500">
          To add or edit spaces, visit the location settings in your venue management.
        </p>
      </div>
    `

        this.spacesContentTarget.innerHTML = html
    }

    async refreshSpacesFromServer(locationId) {
        try {
            const response = await fetch(`/manage/locations/${locationId}.json`)
            if (response.ok) {
                const data = await response.json()
                // Update local locations data
                const locIndex = this.locationsValue.findIndex(l => l.id == locationId)
                if (locIndex >= 0 && data.spaces) {
                    this.locationsValue[locIndex].spaces = data.spaces
                    this.locationChanged()
                }
            }
        } catch (e) {
            console.log("Could not refresh spaces:", e)
        }
    }
}
