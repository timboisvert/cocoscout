import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["popup", "popupTitle", "popupContent", "rolesData", "slotSelect"]

    connect() {
        this.currentMemberId = null
        this.currentMemberName = null
        this.currentShowId = null
        this.currentCastRoles = []
        this.isSignedUp = false
        this.popupData = null
        this.isMultiShowFormat = false

        // Parse the roles data if available
        if (this.hasRolesDataTarget) {
            try {
                this.popupData = JSON.parse(this.rolesDataTarget.textContent)
                // Check if this is multi-show format (person modal) or single-show format (event modal)
                this.isMultiShowFormat = this.popupData.shows !== undefined
            } catch (e) {
                console.error("Error parsing roles data:", e)
            }
        }

        // Close popup when clicking outside
        document.addEventListener('click', this.handleOutsideClick.bind(this))
        document.addEventListener('keydown', this.handleKeydown.bind(this))
    }

    disconnect() {
        document.removeEventListener('click', this.handleOutsideClick.bind(this))
        document.removeEventListener('keydown', this.handleKeydown.bind(this))
    }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            this.closePopup()
        }
    }

    handleOutsideClick(event) {
        if (!this.hasPopupTarget || this.popupTarget.classList.contains('hidden')) return

        if (!this.popupTarget.contains(event.target) &&
            !event.target.closest('[data-action*="openPopup"]')) {
            this.closePopup()
        }
    }

    openPopup(event) {
        event.stopPropagation()

        const row = event.currentTarget
        this.currentShowId = row.dataset.showId
        this.currentMemberId = row.dataset.memberId
        this.currentMemberName = row.dataset.memberName
        this.currentAvailability = row.dataset.availability || 'unset'

        try {
            this.currentCastRoles = JSON.parse(row.dataset.castRoles || '[]')
        } catch (e) {
            this.currentCastRoles = []
        }

        this.isSignedUp = row.dataset.isSignedUp === 'true'

        // Build popup content
        this.buildPopupContent()

        // Position and show popup
        const rect = row.getBoundingClientRect()
        const popup = this.popupTarget

        popup.classList.remove('hidden')

        // Position near the row
        const popupWidth = popup.offsetWidth
        const popupHeight = popup.offsetHeight
        const spaceOnRight = window.innerWidth - rect.right
        const spaceBelow = window.innerHeight - rect.bottom

        // Horizontal positioning
        if (spaceOnRight >= popupWidth + 20) {
            popup.style.left = `${rect.right + 10}px`
        } else {
            popup.style.left = `${Math.max(10, rect.left - popupWidth - 10)}px`
        }

        // Vertical positioning
        if (spaceBelow >= popupHeight + 10) {
            popup.style.top = `${rect.top + window.scrollY}px`
        } else {
            popup.style.top = `${Math.max(10, rect.bottom + window.scrollY - popupHeight)}px`
        }
    }

    closePopup() {
        if (this.hasPopupTarget) {
            this.popupTarget.classList.add('hidden')
        }
        this.currentMemberId = null
        this.currentShowId = null
    }

    formatSlotLabel(slot, slotMode) {
        if (slotMode === 'numbered') {
            return `Position ${slot.position}`
        } else if (slotMode === 'time_based' && slot.name) {
            return slot.name
        } else if (slotMode === 'named' && slot.name) {
            return slot.name
        } else {
            return `Slot ${slot.position}`
        }
    }

    buildPopupContent() {
        if (!this.popupData) {
            this.popupContentTarget.innerHTML = '<div class="text-sm text-gray-500">No actions available</div>'
            return
        }

        // Get the roles and sign-up form for the current show
        let roles, signUpForm
        if (this.isMultiShowFormat) {
            // Person modal format: data.shows[showId]
            const showData = this.popupData.shows[this.currentShowId]
            if (!showData) {
                this.popupContentTarget.innerHTML = '<div class="text-sm text-gray-500">No data for this show</div>'
                return
            }
            roles = showData.roles || []
            signUpForm = showData.sign_up_form
        } else {
            // Event modal format: data.roles, data.sign_up_form
            roles = this.popupData.roles || []
            signUpForm = this.popupData.sign_up_form
        }

        let html = ''

        // Availability section - always at the top
        html += '<div class="text-xs font-medium text-gray-500 uppercase mb-1">Availability</div>'
        html += '<div class="flex gap-2 mb-3">'

        const isAvailable = this.currentAvailability === 'available'
        const isUnavailable = this.currentAvailability === 'unavailable'

        // Button styles matching shared/button
        const primaryClasses = "inline-flex items-center justify-center gap-2 font-medium rounded transition-colors cursor-pointer bg-pink-500 text-white px-3 py-1.5 text-sm"
        const secondaryClasses = "inline-flex items-center justify-center gap-2 font-medium rounded transition-colors cursor-pointer bg-white border border-gray-300 hover:bg-gray-50 text-gray-700 px-3 py-1.5 text-sm"

        // Available button
        if (isAvailable) {
            html += `
                <div class="flex-1 ${primaryClasses}">
                    <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                        <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
                    </svg>
                    Available
                </div>`
        } else {
            html += `
                <button type="button"
                    data-action="click->availability-popup#setAvailability"
                    data-status="available"
                    class="flex-1 ${secondaryClasses}">
                    Available
                </button>`
        }

        // Unavailable button
        if (isUnavailable) {
            html += `
                <div class="flex-1 ${primaryClasses}">
                    <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                        <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
                    </svg>
                    Unavailable
                </div>`
        } else {
            html += `
                <button type="button"
                    data-action="click->availability-popup#setAvailability"
                    data-status="unavailable"
                    class="flex-1 ${secondaryClasses}">
                    Unavailable
                </button>`
        }

        html += '</div>'

        // Roles section
        if (roles.length > 0) {
            html += '<div class="text-xs font-medium text-gray-500 uppercase mb-1">Cast as...</div>'

            roles.forEach(role => {
                const isAlreadyCast = this.currentCastRoles.includes(role.name)
                const isFullyCast = role.current_count >= role.quantity
                const availableSlots = role.quantity - role.current_count

                // Check eligibility for restricted roles
                let isEligible = true
                if (role.restricted && role.eligible_members) {
                    isEligible = role.eligible_members.some(m => m.type === 'Person' && m.id === parseInt(this.currentMemberId))
                }

                // Build label
                let label = role.name
                let sublabel = ''

                if (role.quantity > 1) {
                    sublabel = `${role.current_count}/${role.quantity} cast`
                }

                if (isAlreadyCast) {
                    // Already cast in this role - show as non-clickable with checkmark
                    html += `
                        <div class="w-full text-left px-3 py-2 text-sm rounded text-pink-600 bg-pink-50 flex items-center gap-2">
                            <svg class="w-4 h-4 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
                                <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
                            </svg>
                            <span class="flex-1">${label} <span class="text-xs">(cast)</span></span>
                        </div>`
                } else if (isFullyCast) {
                    // Role is fully cast
                    html += `
                        <div class="w-full text-left px-3 py-2 text-sm rounded text-gray-400 cursor-not-allowed">
                            ${label} <span class="text-xs">(fully cast)</span>
                        </div>`
                } else if (role.restricted && !isEligible) {
                    // Not eligible for restricted role
                    html += `
                        <button type="button"
                                class="w-full text-left px-3 py-2 text-sm rounded text-amber-600 hover:bg-amber-50 transition-colors cursor-pointer flex items-center gap-2"
                                data-action="click->availability-popup#confirmIneligible"
                                data-role-id="${role.id}"
                                data-role-name="${role.name}">
                            <svg class="w-4 h-4 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
                                <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
                            </svg>
                            <span class="flex-1">${label} <span class="text-xs">(not eligible)</span></span>
                        </button>`
                } else {
                    // Available to cast
                    html += `
                        <button type="button"
                                class="w-full text-left px-3 py-2 text-sm rounded hover:bg-pink-50 hover:text-pink-700 transition-colors cursor-pointer"
                                data-action="click->availability-popup#castPerson"
                                data-role-id="${role.id}"
                                data-role-name="${role.name}">
                            ${label}${sublabel ? ` <span class="text-xs text-gray-400">(${sublabel})</span>` : ''}
                        </button>`
                }
            })
        } else if (!signUpForm) {
            // Only show "no roles" message if there's also no sign-up form
            html += '<div class="text-sm text-gray-500 py-1">No roles defined for this show</div>'
        }

        // Sign-up section
        if (signUpForm) {
            // Don't show registration options for past events that are closed
            if (signUpForm.show_in_past && !signUpForm.is_open) {
                // Past event, closed - don't show registration option
            } else if (!signUpForm.is_open && !signUpForm.can_pre_register) {
                // Form not open and pre-registration not allowed - don't show
            } else {
                html += '<div class="border-t border-gray-200 my-2"></div>'
                html += '<div class="text-xs font-medium text-gray-500 uppercase mb-1"/manage/ticketing/providers/12</div>'

                if (this.isSignedUp) {
                    html += '<div class="px-3 py-2 text-sm text-gray-400">Already registered</div>'
                } else if (signUpForm.slot_mode === 'open_list') {
                    // Open list - single button to register (no slot mention)
                    const buttonText = signUpForm.is_open ? 'Register' : 'Pre-register'
                    html += `
                        <button type="button"
                                class="w-full text-left px-3 py-2 text-sm rounded hover:bg-pink-50 hover:text-pink-700 transition-colors cursor-pointer"
                                data-action="click->availability-popup#registerPerson">
                            ${buttonText}
                        </button>`
                } else {
                    // Numbered, named, or time-based slots
                    const availableSlots = (signUpForm.slots || []).filter(s => s.available)

                    if (availableSlots.length === 0) {
                        html += '<div class="px-3 py-2 text-sm text-gray-400">No slots available</div>'
                    } else {
                        const actionText = signUpForm.is_open ? 'Register' : 'Pre-register'
                        const slotTypeLabel = signUpForm.slot_mode === 'time_based' ? 'time' : 'slot'

                        // Option 1: Next available slot
                        const firstSlot = availableSlots[0]
                        const firstSlotLabel = this.formatSlotLabel(firstSlot, signUpForm.slot_mode)
                        html += `
                            <button type="button"
                                    class="w-full text-left px-3 py-2 text-sm rounded hover:bg-pink-50 hover:text-pink-700 transition-colors cursor-pointer"
                                    data-action="click->availability-popup#registerForSlot"
                                    data-slot-id="${firstSlot.id}">
                                ${actionText} <span class="text-xs text-gray-400">(next: ${firstSlotLabel})</span>
                            </button>`

                        // Option 2: Choose a specific slot (only if more than 1 available)
                        if (availableSlots.length > 1) {
                            let optionsHtml = availableSlots.map(slot => {
                                const label = this.formatSlotLabel(slot, signUpForm.slot_mode)
                                return `<option value="${slot.id}">${label}</option>`
                            }).join('')

                            html += `
                                <div class="flex items-center gap-2 px-3 py-2">
                                    <span class="text-sm text-gray-600">or choose:</span>
                                    <select class="flex-1 text-sm border border-gray-300 rounded px-2 py-1 focus:outline-none focus:ring-1 focus:ring-pink-500"
                                            data-availability-popup-target="slotSelect">
                                        ${optionsHtml}
                                    </select>
                                    <button type="button"
                                            class="px-3 py-1 text-sm rounded bg-pink-500 text-white hover:bg-pink-600 transition-colors cursor-pointer"
                                            data-action="click->availability-popup#registerSelectedSlot">
                                        Go
                                    </button>
                                </div>`
                        }
                    }
                }
            }
        }

        this.popupContentTarget.innerHTML = html
        this.popupTitleTarget.textContent = this.currentMemberName || 'Actions'
    }

    confirmRecast(event) {
        event.stopPropagation()
        const roleId = event.currentTarget.dataset.roleId
        const roleName = event.currentTarget.dataset.roleName

        this.popupContentTarget.innerHTML = `
            <div class="space-y-3">
                <div class="text-sm">
                    <div class="flex items-center gap-1 text-amber-600 font-medium mb-1">
                        <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                            <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
                        </svg>
                        Already cast as ${roleName}
                    </div>
                    <p class="text-gray-600 text-xs">
                        <span class="font-medium">${this.currentMemberName}</span> is already cast in this role.
                        Add another assignment anyway?
                    </p>
                </div>
                <div class="flex gap-2 pt-1">
                    <button type="button" class="flex-1 px-3 py-1.5 text-xs rounded border border-gray-300 text-gray-700 hover:bg-gray-50 transition-colors cursor-pointer"
                            data-action="click->availability-popup#buildPopupContent">
                        Cancel
                    </button>
                    <button type="button" class="flex-1 px-3 py-1.5 text-xs rounded bg-amber-500 text-white hover:bg-amber-600 transition-colors cursor-pointer"
                            data-action="click->availability-popup#castPerson"
                            data-role-id="${roleId}">
                        Add Assignment
                    </button>
                </div>
            </div>
        `
    }

    confirmIneligible(event) {
        event.stopPropagation()
        const roleId = event.currentTarget.dataset.roleId
        const roleName = event.currentTarget.dataset.roleName

        this.popupContentTarget.innerHTML = `
            <div class="space-y-3">
                <div class="text-sm">
                    <div class="flex items-center gap-1 text-amber-600 font-medium mb-1">
                        <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                            <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
                        </svg>
                        ${roleName} is restricted
                    </div>
                    <p class="text-gray-600 text-xs">
                        <span class="font-medium">${this.currentMemberName}</span> is not in the eligible list for this role.
                        Assign anyway?
                    </p>
                </div>
                <div class="flex gap-2 pt-1">
                    <button type="button" class="flex-1 px-3 py-1.5 text-xs rounded border border-gray-300 text-gray-700 hover:bg-gray-50 transition-colors cursor-pointer"
                            data-action="click->availability-popup#buildPopupContent">
                        Cancel
                    </button>
                    <button type="button" class="flex-1 px-3 py-1.5 text-xs rounded bg-amber-500 text-white hover:bg-amber-600 transition-colors cursor-pointer"
                            data-action="click->availability-popup#castPerson"
                            data-role-id="${roleId}">
                        Assign Anyway
                    </button>
                </div>
            </div>
        `
    }

    async setAvailability(event) {
        event.stopPropagation()
        const status = event.currentTarget.dataset.status
        const csrfToken = document.querySelector('meta[name="csrf-token"]').content

        try {
            const response = await fetch("/manage/casting/availability/set_availability", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": csrfToken
                },
                body: JSON.stringify({
                    show_id: this.currentShowId,
                    person_id: this.currentMemberId,
                    status: status
                })
            })

            const result = await response.json()

            if (result.success) {
                this.closePopup()
                this.dispatchRefreshEvent()
            } else {
                alert(result.error || "Failed to update availability")
            }
        } catch (error) {
            console.error("Error updating availability:", error)
            alert("An error occurred")
        }
    }

    async castPerson(event) {
        event.stopPropagation()
        const roleId = event.currentTarget.dataset.roleId
        const csrfToken = document.querySelector('meta[name="csrf-token"]').content

        try {
            const response = await fetch("/manage/casting/availability/cast_person", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": csrfToken
                },
                body: JSON.stringify({
                    show_id: this.currentShowId,
                    role_id: roleId,
                    person_id: this.currentMemberId
                })
            })

            const result = await response.json()

            if (result.success) {
                this.closePopup()
                this.dispatchRefreshEvent()
            } else {
                alert(result.error || "Failed to cast person")
            }
        } catch (error) {
            console.error("Error casting person:", error)
            alert("An error occurred")
        }
    }

    async signUpPerson(event) {
        // Legacy method - redirect to registerPerson
        return this.registerPerson(event)
    }

    async registerPerson(event) {
        event.stopPropagation()
        const csrfToken = document.querySelector('meta[name="csrf-token"]').content

        try {
            const response = await fetch("/manage/casting/availability/register_person", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": csrfToken
                },
                body: JSON.stringify({
                    show_id: this.currentShowId,
                    person_id: this.currentMemberId
                })
            })

            const result = await response.json()

            if (result.success) {
                this.closePopup()
                this.dispatchRefreshEvent()
            } else {
                alert(result.error || "Failed to register person")
            }
        } catch (error) {
            console.error("Error registering person:", error)
            alert("An error occurred")
        }
    }

    async registerForSlot(event) {
        event.stopPropagation()
        const slotId = event.currentTarget.dataset.slotId
        const csrfToken = document.querySelector('meta[name="csrf-token"]').content

        try {
            const response = await fetch("/manage/casting/availability/register_person", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": csrfToken
                },
                body: JSON.stringify({
                    show_id: this.currentShowId,
                    person_id: this.currentMemberId,
                    slot_id: slotId
                })
            })

            const result = await response.json()

            if (result.success) {
                this.closePopup()
                this.dispatchRefreshEvent()
            } else {
                alert(result.error || "Failed to register person")
            }
        } catch (error) {
            console.error("Error registering person:", error)
            alert("An error occurred")
        }
    }

    async registerSelectedSlot(event) {
        event.stopPropagation()

        if (!this.hasSlotSelectTarget) {
            alert("Please select a slot")
            return
        }

        const slotId = this.slotSelectTarget.value
        const csrfToken = document.querySelector('meta[name="csrf-token"]').content

        try {
            const response = await fetch("/manage/casting/availability/register_person", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": csrfToken
                },
                body: JSON.stringify({
                    show_id: this.currentShowId,
                    person_id: this.currentMemberId,
                    slot_id: slotId
                })
            })

            const result = await response.json()

            if (result.success) {
                this.closePopup()
                this.dispatchRefreshEvent()
            } else {
                alert(result.error || "Failed to register person")
            }
        } catch (error) {
            console.error("Error registering person:", error)
            alert("An error occurred")
        }
    }

    async preRegister(event) {
        event.stopPropagation()

        // Show confirmation in popup
        this.popupContentTarget.innerHTML = `
            <div class="space-y-3">
                <div class="text-sm">
                    <div class="flex items-center gap-1 text-purple-600 font-medium mb-1">
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
                        </svg>
                        Pre-Registration
                    </div>
                    <p class="text-gray-600 text-xs mb-2">
                        The sign-up form hasn't opened yet. Pre-register <span class="font-medium">${this.currentMemberName}</span>?
                    </p>
                    <p class="text-gray-500 text-xs">
                        They'll be added to the queue and notified by email.
                    </p>
                </div>
                <div class="flex gap-2 pt-1">
                    <button type="button" class="flex-1 px-3 py-1.5 text-xs rounded border border-gray-300 text-gray-700 hover:bg-gray-50 transition-colors cursor-pointer"
                            data-action="click->availability-popup#buildPopupContent">
                        Cancel
                    </button>
                    <button type="button" class="flex-1 px-3 py-1.5 text-xs rounded bg-purple-500 text-white hover:bg-purple-600 transition-colors cursor-pointer"
                            data-action="click->availability-popup#confirmPreRegister">
                        Pre-Register
                    </button>
                </div>
            </div>
        `
    }

    async confirmPreRegister(event) {
        event.stopPropagation()
        const csrfToken = document.querySelector('meta[name="csrf-token"]').content

        try {
            const response = await fetch("/manage/casting/availability/pre_register", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": csrfToken
                },
                body: JSON.stringify({
                    show_id: this.currentShowId,
                    person_id: this.currentMemberId,
                    send_email: true
                })
            })

            const result = await response.json()

            if (result.success) {
                this.closePopup()
                this.dispatchRefreshEvent()
            } else {
                alert(result.error || "Failed to pre-register person")
            }
        } catch (error) {
            console.error("Error pre-registering person:", error)
            alert("An error occurred")
        }
    }

    dispatchRefreshEvent() {
        // Dispatch a custom event that the parent controller can listen to
        const event = new CustomEvent('availability-popup:refresh', {
            bubbles: true,
            detail: { showId: this.currentShowId, memberId: this.currentMemberId }
        })
        this.element.dispatchEvent(event)
    }
}
