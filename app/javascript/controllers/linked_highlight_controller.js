import { Controller } from "@hotwired/stimulus"

// Highlights all linked shows when hovering over any one of them
// Usage: Add data-controller="linked-highlight" to a container
//        Add data-linked-highlight-target="row" data-linkage-id="123" to each row
export default class extends Controller {
    static targets = ["row"]

    connect() {
        this.rowTargets.forEach(row => {
            row.addEventListener("mouseenter", this.handleMouseEnter.bind(this))
            row.addEventListener("mouseleave", this.handleMouseLeave.bind(this))
        })
    }

    disconnect() {
        this.rowTargets.forEach(row => {
            row.removeEventListener("mouseenter", this.handleMouseEnter.bind(this))
            row.removeEventListener("mouseleave", this.handleMouseLeave.bind(this))
        })
    }

    handleMouseEnter(event) {
        const linkageId = event.currentTarget.dataset.linkageId
        if (!linkageId) return

        // Highlight all rows with the same linkage ID
        this.rowTargets.forEach(row => {
            if (row.dataset.linkageId === linkageId) {
                row.classList.add("linked-highlight")
            }
        })
    }

    handleMouseLeave(event) {
        const linkageId = event.currentTarget.dataset.linkageId
        if (!linkageId) return

        // Remove highlight from all rows with the same linkage ID
        this.rowTargets.forEach(row => {
            if (row.dataset.linkageId === linkageId) {
                row.classList.remove("linked-highlight")
            }
        })
    }
}
