import { Controller } from "@hotwired/stimulus"

// Handles the zones container
// - Updates total capacity across all zones
// - Manages zone addition/removal
export default class extends Controller {
    static targets = ["container", "totalCapacity", "summary"]

    connect() {
        this.updateTotal()
    }

    updateTotal() {
        // Small delay to allow individual zone controllers to update first
        requestAnimationFrame(() => {
            const zones = this.containerTarget.querySelectorAll(".nested-fields:not([style*='display: none'])")
            let total = 0

            zones.forEach(zone => {
                const capacityElement = zone.querySelector("[data-seating-zone-target='capacity']")
                if (capacityElement) {
                    total += parseInt(capacityElement.textContent, 10) || 0
                }
            })

            if (this.hasTotalCapacityTarget) {
                this.totalCapacityTarget.textContent = total
            }
        })
    }
}
