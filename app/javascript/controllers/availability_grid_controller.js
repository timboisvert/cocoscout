import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["row", "cell"]
    static values = { refreshUrl: String }

    connect() {
        this.currentColumn = null
        // Listen for refresh event from modal
        this.refreshHandler = this.refresh.bind(this)
        document.addEventListener('availability-grid:refresh', this.refreshHandler)
    }

    disconnect() {
        document.removeEventListener('availability-grid:refresh', this.refreshHandler)
    }

    async refresh() {
        // Use Turbo to refresh the page
        const currentUrl = window.location.href
        try {
            const response = await fetch(currentUrl, {
                headers: {
                    'Accept': 'text/html',
                    'X-Requested-With': 'XMLHttpRequest'
                }
            })
            if (response.ok) {
                // Use Turbo to handle the response
                Turbo.visit(currentUrl, { action: 'replace' })
            }
        } catch (error) {
            console.error('Failed to refresh grid:', error)
        }
    }

    highlightColumn(event) {
        const colIndex = event.currentTarget.dataset.col
        if (colIndex === undefined) return

        // Clear any previous column highlight
        if (this.currentColumn !== null && this.currentColumn !== colIndex) {
            this.clearColumnHighlight(this.currentColumn)
        }

        this.currentColumn = colIndex

        // Find all cells and headers in this column
        const cells = this.element.querySelectorAll(`[data-col="${colIndex}"]`)
        cells.forEach(cell => {
            cell.classList.add('column-hover')
        })
    }

    unhighlightColumn(event) {
        const colIndex = event.currentTarget.dataset.col
        if (colIndex === undefined) return

        this.clearColumnHighlight(colIndex)
        this.currentColumn = null
    }

    clearColumnHighlight(colIndex) {
        // Find all cells and headers in this column
        const cells = this.element.querySelectorAll(`[data-col="${colIndex}"]`)
        cells.forEach(cell => {
            cell.classList.remove('column-hover')
        })
    }
}
