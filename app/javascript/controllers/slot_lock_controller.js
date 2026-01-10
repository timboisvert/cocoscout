import { Controller } from "@hotwired/stimulus"

// Controller for handling 60-second slot locks during sign-up
// Acquires a lock when user clicks a slot, shows countdown, auto-releases on expiry
export default class extends Controller {
    static targets = ["slot", "countdown", "countdownTime", "lockedOverlay", "expiredOverlay", "modalFooter"]

    static values = {
        lockUrl: String,
        unlockUrl: String,
        beaconUnlockUrl: String, // POST version for sendBeacon on page unload
        locksUrl: String,
        pollInterval: { type: Number, default: 10000 }
    }

    connect() {
        this.lockedSlotId = null
        this.lockTimer = null
        this.countdownTimer = null
        this.expiresAt = null

        // Poll for lock status updates from other users
        this.startPolling()

        // Release lock when user leaves page
        window.addEventListener('beforeunload', this.handleBeforeUnload.bind(this))
    }

    disconnect() {
        this.stopPolling()
        this.clearTimers()
        window.removeEventListener('beforeunload', this.handleBeforeUnload.bind(this))

        // Release any held lock
        if (this.lockedSlotId) {
            this.releaseLock(this.lockedSlotId)
        }
    }

    // Called when user clicks a slot to select it
    // This must stop the event and re-dispatch after lock is acquired
    async selectSlot(event) {
        // Always stop propagation - we'll manually trigger sign-up-confirmation if lock succeeds
        event.stopImmediatePropagation()
        event.preventDefault()

        const slotElement = event.currentTarget
        const slotId = slotElement.dataset.slotId

        // Hide expired overlay if visible (user is trying again)
        if (this.hasExpiredOverlayTarget) {
            this.expiredOverlayTarget.classList.add('hidden')
        }

        // If we already have this slot locked, proceed to confirmation
        if (this.lockedSlotId === slotId) {
            this.dispatchToConfirmation(slotElement)
            return
        }

        // Release any existing lock first
        if (this.lockedSlotId) {
            await this.releaseLock(this.lockedSlotId)
        }

        // Try to acquire lock
        const result = await this.acquireLock(slotId)

        if (result.success) {
            this.lockedSlotId = slotId
            this.startCountdown(result.expires_in)
            this.highlightLockedSlot(slotId)
            // Now trigger the confirmation controller
            this.dispatchToConfirmation(slotElement)
        } else {
            // Show error - slot is locked by someone else
            this.showLockError(slotElement, result.error, result.expires_in)
        }
    }

    // Dispatch to sign-up-confirmation controller after lock acquired
    dispatchToConfirmation(slotElement) {
        // Find the sign-up-confirmation controller on the parent element
        const container = this.element
        const confirmationController = this.application.getControllerForElementAndIdentifier(container, 'sign-up-confirmation')

        if (confirmationController) {
            // Create a fake event object with the methods the controller expects
            const fakeEvent = {
                currentTarget: slotElement,
                target: slotElement,
                preventDefault: () => { },
                stopPropagation: () => { },
                stopImmediatePropagation: () => { }
            }

            // Check if this is a change slot or select slot action
            // by looking at the original action string
            const actionString = slotElement.dataset.action || ''
            if (actionString.includes('changeSlot')) {
                confirmationController.changeSlot(fakeEvent)
            } else {
                confirmationController.selectSlot(fakeEvent)
            }
        }
    }

    async acquireLock(slotId) {
        try {
            const url = this.lockUrlValue.replace(':slot_id', slotId)
            const response = await fetch(url, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
                }
            })
            return await response.json()
        } catch (error) {
            console.error('Failed to acquire lock:', error)
            return { success: false, error: 'Network error' }
        }
    }

    async releaseLock(slotId) {
        try {
            const url = this.unlockUrlValue.replace(':slot_id', slotId)
            await fetch(url, {
                method: 'DELETE',
                headers: {
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
                }
            })
        } catch (error) {
            console.error('Failed to release lock:', error)
        }

        this.clearTimers()
        this.lockedSlotId = null
        this.removeHighlight()
    }

    startCountdown(seconds) {
        this.clearTimers()
        this.expiresAt = Date.now() + (seconds * 1000)

        // Show the countdown container
        if (this.hasCountdownTarget) {
            this.countdownTarget.classList.remove('hidden')
        }

        // Initial display
        this.updateCountdownDisplay(seconds)

        // Update countdown display every second
        this.countdownTimer = setInterval(() => {
            const remaining = Math.max(0, Math.ceil((this.expiresAt - Date.now()) / 1000))
            this.updateCountdownDisplay(remaining)

            if (remaining <= 0) {
                this.handleLockExpired()
            }
        }, 1000)

        // Also set a backup timer for exact expiry
        this.lockTimer = setTimeout(() => {
            this.handleLockExpired()
        }, seconds * 1000)
    }

    updateCountdownDisplay(seconds) {
        if (this.hasCountdownTimeTarget) {
            const minutes = Math.floor(seconds / 60)
            const secs = seconds % 60
            this.countdownTimeTarget.textContent = minutes > 0
                ? `${minutes}:${secs.toString().padStart(2, '0')}`
                : `${secs}s`

            // Add urgency styling when low
            if (seconds <= 10) {
                this.countdownTarget.classList.add('text-red-600', 'animate-pulse')
                this.countdownTarget.classList.remove('text-pink-600')
            } else {
                this.countdownTarget.classList.remove('text-red-600', 'animate-pulse')
                this.countdownTarget.classList.add('text-pink-600')
            }
        }
    }

    handleLockExpired() {
        this.clearTimers()
        this.lockedSlotId = null
        this.removeHighlight()
        this.hideCountdown()

        // Show the expired overlay in the modal
        if (this.hasExpiredOverlayTarget) {
            this.expiredOverlayTarget.classList.remove('hidden')
        }

        // Dispatch event for the form to handle
        this.dispatch('expired', { detail: { message: 'Your slot hold has expired. Please select again.' } })
    }

    closeExpiredModal() {
        // Hide the expired overlay
        if (this.hasExpiredOverlayTarget) {
            this.expiredOverlayTarget.classList.add('hidden')
        }

        // Close the main modal
        const confirmationController = this.application.getControllerForElementAndIdentifier(this.element, 'sign-up-confirmation')
        if (confirmationController) {
            confirmationController.close()
        }
    }

    hideCountdown() {
        if (this.hasCountdownTarget) {
            this.countdownTarget.classList.add('hidden')
        }
    }

    clearTimers() {
        if (this.lockTimer) {
            clearTimeout(this.lockTimer)
            this.lockTimer = null
        }
        if (this.countdownTimer) {
            clearInterval(this.countdownTimer)
            this.countdownTimer = null
        }
    }

    highlightLockedSlot(slotId) {
        // Remove highlight from all slots
        this.slotTargets.forEach(slot => {
            slot.classList.remove('ring-2', 'ring-pink-500', 'bg-pink-50')
        })

        // Add highlight to locked slot
        const lockedSlot = this.slotTargets.find(s => s.dataset.slotId === slotId.toString())
        if (lockedSlot) {
            lockedSlot.classList.add('ring-2', 'ring-pink-500', 'bg-pink-50')
        }
    }

    removeHighlight() {
        this.slotTargets.forEach(slot => {
            slot.classList.remove('ring-2', 'ring-pink-500', 'bg-pink-50')
        })
    }

    showLockError(slotElement, message, expiresIn) {
        // Show a temporary error message
        const existingError = slotElement.querySelector('.lock-error')
        if (existingError) existingError.remove()

        const errorDiv = document.createElement('div')
        errorDiv.className = 'lock-error absolute inset-0 bg-gray-900/75 flex items-center justify-center rounded-lg'
        errorDiv.innerHTML = `
            <div class="text-center text-white px-4">
                <p class="text-sm font-medium">Held by another user</p>
                ${expiresIn ? `<p class="text-xs opacity-75">Available in ~${expiresIn}s</p>` : ''}
            </div>
        `

        slotElement.style.position = 'relative'
        slotElement.appendChild(errorDiv)

        // Remove after 3 seconds
        setTimeout(() => errorDiv.remove(), 3000)
    }

    // Poll for lock updates from other users
    startPolling() {
        if (!this.hasLocksUrlValue) return

        this.pollTimer = setInterval(() => {
            this.fetchLockStatus()
        }, this.pollIntervalValue)
    }

    stopPolling() {
        if (this.pollTimer) {
            clearInterval(this.pollTimer)
            this.pollTimer = null
        }
    }

    async fetchLockStatus() {
        if (!this.hasLocksUrlValue) return

        try {
            const response = await fetch(this.locksUrlValue)
            const data = await response.json()
            this.updateSlotLockDisplay(data.locks)
        } catch (error) {
            console.error('Failed to fetch lock status:', error)
        }
    }

    updateSlotLockDisplay(locks) {
        this.slotTargets.forEach(slot => {
            const slotId = slot.dataset.slotId
            const lockInfo = locks[slotId]

            if (lockInfo?.locked && !lockInfo.locked_by_me) {
                // Slot is locked by someone else - show indicator
                slot.classList.add('opacity-50', 'pointer-events-none')
                if (!slot.querySelector('.other-user-lock')) {
                    const lockBadge = document.createElement('div')
                    lockBadge.className = 'other-user-lock absolute top-1 right-1 bg-yellow-100 text-yellow-800 text-xs px-1.5 py-0.5 rounded'
                    lockBadge.textContent = 'Held'
                    slot.style.position = 'relative'
                    slot.appendChild(lockBadge)
                }
            } else {
                // Slot is available or locked by us
                slot.classList.remove('opacity-50', 'pointer-events-none')
                const lockBadge = slot.querySelector('.other-user-lock')
                if (lockBadge) lockBadge.remove()
            }
        })
    }

    handleBeforeUnload() {
        // Release lock synchronously when leaving page using sendBeacon (which only does POST)
        if (this.lockedSlotId && this.hasBeaconUnlockUrlValue) {
            const url = this.beaconUnlockUrlValue.replace(':slot_id', this.lockedSlotId)
            navigator.sendBeacon(url)
        }
    }
}
