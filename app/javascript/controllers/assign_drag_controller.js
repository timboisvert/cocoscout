import { Controller } from "@hotwired/stimulus"

/**
 * Handles drag and drop for the assign page.
 * Supports:
 * - Dragging from queue to a slot (assigns registration)
 * - Dragging from one slot to another (moves registration)
 */
export default class extends Controller {
    static targets = ["slotList", "queueList", "dropZone", "emptySlot", "draggable", "queueItem"]

    connect() {
        this.setupDragEvents()
    }

    setupDragEvents() {
        // Set up drag start for all draggable items
        this.draggableTargets.forEach(el => {
            el.addEventListener("dragstart", this.handleDragStart.bind(this))
            el.addEventListener("dragend", this.handleDragEnd.bind(this))
        })

        this.queueItemTargets.forEach(el => {
            el.addEventListener("dragstart", this.handleDragStart.bind(this))
            el.addEventListener("dragend", this.handleDragEnd.bind(this))
        })

        // Set up drop zones
        this.dropZoneTargets.forEach(zone => {
            zone.addEventListener("dragover", this.handleDragOver.bind(this))
            zone.addEventListener("dragleave", this.handleDragLeave.bind(this))
            zone.addEventListener("drop", this.handleDrop.bind(this))
        })

        this.emptySlotTargets.forEach(zone => {
            zone.addEventListener("dragover", this.handleDragOver.bind(this))
            zone.addEventListener("dragleave", this.handleDragLeave.bind(this))
            zone.addEventListener("drop", this.handleDrop.bind(this))
        })
    }

    handleDragStart(event) {
        const el = event.target.closest("[data-registration-id]")
        if (!el) return

        this.draggedElement = el
        this.draggedRegistrationId = el.dataset.registrationId
        this.draggedFromSlotId = el.dataset.currentSlotId // undefined for queue items

        el.classList.add("opacity-50")
        event.dataTransfer.effectAllowed = "move"
        event.dataTransfer.setData("text/plain", this.draggedRegistrationId)

        // Highlight valid drop zones
        this.highlightDropZones()
    }

    handleDragEnd(event) {
        if (this.draggedElement) {
            this.draggedElement.classList.remove("opacity-50")
        }
        this.clearHighlights()
        this.draggedElement = null
        this.draggedRegistrationId = null
        this.draggedFromSlotId = null
    }

    handleDragOver(event) {
        event.preventDefault()
        const zone = event.currentTarget
        const slotId = zone.dataset.slotId

        // Check if slot has capacity
        const capacity = parseInt(zone.dataset.slotCapacity || "1")
        const count = parseInt(zone.dataset.slotCount || "0")

        // Allow drop if it's a different slot than where it came from and has capacity
        // (or if same slot for reordering, though we're not implementing reorder)
        if (slotId !== this.draggedFromSlotId && count < capacity) {
            zone.classList.add("bg-pink-50", "border-pink-300")
            event.dataTransfer.dropEffect = "move"
        } else if (slotId === this.draggedFromSlotId) {
            // Same slot - we could allow reordering here
            event.dataTransfer.dropEffect = "none"
        } else {
            event.dataTransfer.dropEffect = "none"
        }
    }

    handleDragLeave(event) {
        const zone = event.currentTarget
        zone.classList.remove("bg-pink-50", "border-pink-300")
    }

    handleDrop(event) {
        event.preventDefault()
        const zone = event.currentTarget
        zone.classList.remove("bg-pink-50", "border-pink-300")

        const slotId = zone.dataset.slotId
        if (!slotId || !this.draggedRegistrationId) return

        // Check capacity
        const capacity = parseInt(zone.dataset.slotCapacity || "1")
        const count = parseInt(zone.dataset.slotCount || "0")

        if (count >= capacity && slotId !== this.draggedFromSlotId) {
            console.log("Slot is full")
            return
        }

        // Don't allow dropping in same slot
        if (slotId === this.draggedFromSlotId) {
            return
        }

        // Build the assign URL and submit
        this.assignToSlot(this.draggedRegistrationId, slotId)
    }

    highlightDropZones() {
        // Highlight all valid drop zones
        this.dropZoneTargets.forEach(zone => {
            const slotId = zone.dataset.slotId
            const capacity = parseInt(zone.dataset.slotCapacity || "1")
            const count = parseInt(zone.dataset.slotCount || "0")

            if (slotId !== this.draggedFromSlotId && count < capacity) {
                zone.classList.add("ring-2", "ring-pink-200")
            }
        })

        this.emptySlotTargets.forEach(zone => {
            zone.classList.add("ring-2", "ring-pink-200")
        })
    }

    clearHighlights() {
        this.dropZoneTargets.forEach(zone => {
            zone.classList.remove("ring-2", "ring-pink-200", "bg-pink-50", "border-pink-300")
        })

        this.emptySlotTargets.forEach(zone => {
            zone.classList.remove("ring-2", "ring-pink-200", "bg-pink-50", "border-pink-300")
        })
    }

    assignToSlot(registrationId, slotId) {
        // Get current URL to extract production_id, sign_up_form_id, and instance_id
        const url = new URL(window.location.href)
        const pathParts = url.pathname.split("/")

        // Path is like /manage/productions/:prod_id/sign-ups/:form_id/assign
        const productionIndex = pathParts.indexOf("productions")
        const signUpsIndex = pathParts.indexOf("sign-ups")

        if (productionIndex === -1 || signUpsIndex === -1) {
            console.error("Could not parse URL for assign action")
            return
        }

        const productionId = pathParts[productionIndex + 1]
        const formId = pathParts[signUpsIndex + 1]
        const instanceId = url.searchParams.get("instance_id")

        // Build the assign URL
        let assignUrl = `/manage/productions/${productionId}/sign-ups/${formId}/assign_registration/${registrationId}?slot_id=${slotId}`
        if (instanceId) {
            assignUrl += `&instance_id=${instanceId}`
        }

        // Create a form and submit it
        const form = document.createElement("form")
        form.method = "POST"
        form.action = assignUrl

        // Add CSRF token
        const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
        if (csrfToken) {
            const csrfInput = document.createElement("input")
            csrfInput.type = "hidden"
            csrfInput.name = "authenticity_token"
            csrfInput.value = csrfToken
            form.appendChild(csrfInput)
        }

        // Add method override for PATCH
        const methodInput = document.createElement("input")
        methodInput.type = "hidden"
        methodInput.name = "_method"
        methodInput.value = "patch"
        form.appendChild(methodInput)

        document.body.appendChild(form)
        form.submit()
    }
}
