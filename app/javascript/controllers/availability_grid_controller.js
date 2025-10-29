import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["row", "cell"]

    connect() {
        this.currentColumn = null
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
