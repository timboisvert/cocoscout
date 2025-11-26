import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["list"]

    connect() {
        this.availabilityFilter = "available"
        this.castFilter = ""
        this.updateActiveButton()
        this.applyFilters()
    }

    filterByAvailability(event) {
        event.preventDefault()
        const button = event.currentTarget
        this.availabilityFilter = button.dataset.value
        this.updateActiveButton()
        this.applyFilters()
    }

    filterByCast(event) {
        this.castFilter = event.target.value
        this.applyFilters()
    }

    updateActiveButton() {
        // Update which button appears active
        const buttons = this.element.querySelectorAll('[data-action*="filterByAvailability"]')
        buttons.forEach(btn => {
            if (btn.dataset.value === this.availabilityFilter) {
                btn.classList.remove('bg-white', 'text-gray-700', 'border-gray-200', 'hover:border-gray-300')
                btn.classList.add('bg-pink-500', 'text-white', 'border-pink-500')
            } else {
                btn.classList.remove('bg-pink-500', 'text-white', 'border-pink-500')
                btn.classList.add('bg-white', 'text-gray-700', 'border-gray-200', 'hover:border-gray-300')
            }
        })

        // Show/hide availability matrix link based on filter
        const matrixLink = document.getElementById('availability-matrix-link')
        if (matrixLink) {
            if (this.availabilityFilter === "available") {
                matrixLink.classList.remove('hidden')
            } else {
                matrixLink.classList.add('hidden')
            }
        }
    }

    applyFilters() {
        // Find the list container - use the list target
        const listContainer = this.hasListTarget ? this.listTarget : this.element.nextElementSibling

        if (!listContainer) return

        const castMembers = listContainer.querySelectorAll('[data-drag-cast-member-target="person"], [data-drag-cast-member-target="group"]')
        const castHeaders = listContainer.querySelectorAll('h3')
        const castContainers = listContainer.querySelectorAll('.mb-3')

        castMembers.forEach(member => {
            let shouldShow = true

            // Check availability filter
            if (this.availabilityFilter === "available") {
                // Only show if entity marked themselves as available (data-is-available="true")
                // This will show them whether or not they're assigned (opacity-50 handles assignment styling)
                const isAvailable = member.dataset.isAvailable === 'true'
                shouldShow = isAvailable
            }

            // Check cast filter
            if (this.castFilter && shouldShow) {
                const memberCastId = member.dataset.castId
                shouldShow = memberCastId === this.castFilter
            }

            member.style.display = shouldShow ? '' : 'none'
        })

        // Hide cast headers if all their people are hidden (only relevant for multi-cast)
        castHeaders.forEach((header, index) => {
            const container = castContainers[index]
            if (container) {
                const visibleMembers = container.querySelectorAll('[data-drag-cast-member-target="person"]:not([style*="display: none"])')
                container.style.display = visibleMembers.length > 0 ? '' : 'none'
            }
        })

        // Check if there are any visible people
        const visibleMembers = listContainer.querySelectorAll('[data-drag-cast-member-target="person"]:not([style*="display: none"])')
        const emptyState = document.getElementById('cast-members-empty-state')
        const messageElement = document.getElementById('empty-state-message')

        if (visibleMembers.length === 0 && this.availabilityFilter === "available") {
            // Show empty state
            if (emptyState && messageElement) {
                // Determine the message
                const hasMultipleCasts = castHeaders.length > 1
                let message = ""

                if (hasMultipleCasts && this.castFilter) {
                    // Get the cast name
                    const selectedCast = document.querySelector(`select option[value="${this.castFilter}"]`)
                    const castName = selectedCast ? selectedCast.textContent : "this cast"
                    message = `No one in the ${castName} cast is available for this show.`
                } else if (hasMultipleCasts) {
                    message = "No one in any cast is available for this show."
                } else {
                    message = "No one in this cast is available for this show."
                }

                messageElement.textContent = message
                emptyState.classList.remove('hidden')
            }
        } else if (emptyState) {
            // Hide empty state
            emptyState.classList.add('hidden')
        }
    }
}
