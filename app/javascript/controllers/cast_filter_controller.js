import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["list", "roleFilter"]
    static values = {
        isLinked: Boolean,
        linkedCount: Number
    }

    connect() {
        // Default filter depends on whether this is a linked show
        this.availabilityFilter = this.isLinkedValue ? "fully-available" : "available"
        this.castFilter = ""
        this.roleFilter = ""
        this.eligibleByRole = {}

        // Load eligible member data if role filter exists
        if (this.hasRoleFilterTarget) {
            const eligibleData = this.roleFilterTarget.dataset.eligibleByRole
            if (eligibleData) {
                this.eligibleByRole = JSON.parse(eligibleData)
            }
        }

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

    filterByRole(event) {
        this.roleFilter = event.target.value
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
                const isAvailable = member.dataset.isAvailable === 'true'
                shouldShow = isAvailable
            } else if (this.availabilityFilter === "fully-available") {
                // Only show if available for this show AND all linked shows
                const isFullyAvailable = member.dataset.isFullyAvailable === 'true'
                shouldShow = isFullyAvailable
            } else if (this.availabilityFilter === "partially-available") {
                // Show if available for this show OR any linked shows
                const isPartiallyAvailable = member.dataset.isPartiallyAvailable === 'true'
                shouldShow = isPartiallyAvailable
            }
            // else: "all" - show everyone

            // Check cast filter
            if (this.castFilter && shouldShow) {
                const memberCastId = member.dataset.castId
                shouldShow = memberCastId === this.castFilter
            }

            // Check role eligibility filter
            if (this.roleFilter && shouldShow) {
                const eligibleMembers = this.eligibleByRole[this.roleFilter] || []
                // Build the member key in format "Person_123" or "Group_456"
                const isGroup = member.dataset.dragCastMemberTarget === 'group'
                const memberId = isGroup ? member.dataset.groupId : member.dataset.personId
                const memberKey = `${isGroup ? 'Group' : 'Person'}_${memberId}`
                shouldShow = eligibleMembers.includes(memberKey)
            }

            member.style.display = shouldShow ? '' : 'none'

            // Show/hide availability text based on filter
            const availabilityText = member.querySelector('[data-availability-text]')
            if (availabilityText) {
                // Show the availability text for fully-available and partially-available filters
                if ((this.availabilityFilter === "fully-available" || this.availabilityFilter === "partially-available") && shouldShow) {
                    availabilityText.classList.remove('hidden')
                } else {
                    availabilityText.classList.add('hidden')
                }
            }
        })

        // Hide cast headers if all their members are hidden (only relevant for multi-cast)
        castHeaders.forEach((header, index) => {
            const container = castContainers[index]
            if (container) {
                const visibleMembers = container.querySelectorAll('[data-drag-cast-member-target="person"]:not([style*="display: none"]), [data-drag-cast-member-target="group"]:not([style*="display: none"])')
                container.style.display = visibleMembers.length > 0 ? '' : 'none'
            }
        })

        // Check if there are any visible members (people OR groups)
        const visibleMembers = listContainer.querySelectorAll('[data-drag-cast-member-target="person"]:not([style*="display: none"]), [data-drag-cast-member-target="group"]:not([style*="display: none"])')
        const emptyState = document.getElementById('cast-members-empty-state')
        const messageElement = document.getElementById('empty-state-message')

        if (visibleMembers.length === 0 && (this.availabilityFilter !== "all" || this.roleFilter)) {
            // Show empty state
            if (emptyState && messageElement) {
                // Determine the message based on filter type
                let message = ""
                if (this.roleFilter) {
                    // Get the role name from the selected option
                    const selectedOption = this.hasRoleFilterTarget ?
                        this.roleFilterTarget.options[this.roleFilterTarget.selectedIndex] : null
                    const roleName = selectedOption ? selectedOption.text : "this role"
                    message = `No one in the talent pool is approved for ${roleName}.`
                } else if (this.availabilityFilter === "fully-available") {
                    message = "No one in the talent pool is available for all linked events."
                } else if (this.availabilityFilter === "partially-available") {
                    message = "No one in the talent pool is available for any linked events."
                } else {
                    message = "No one in this talent pool is available for this show."
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
