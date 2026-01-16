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
        // Save scroll positions before refresh
        const scrollX = window.scrollX
        const scrollY = window.scrollY
        const gridScrollLeft = this.element.scrollLeft
        const gridScrollTop = this.element.scrollTop

        // Use Turbo to refresh the page, preserving scroll
        const currentUrl = window.location.href

        // Listen for Turbo render to restore scroll position
        const restoreScroll = () => {
            window.scrollTo(scrollX, scrollY)
            // Find the grid element again and restore its scroll
            const grid = document.querySelector('[data-controller="availability-grid"]')
            if (grid) {
                grid.scrollLeft = gridScrollLeft
                grid.scrollTop = gridScrollTop
            }
            document.removeEventListener('turbo:render', restoreScroll)
        }
        document.addEventListener('turbo:render', restoreScroll)

        Turbo.visit(currentUrl, { action: 'replace' })
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
