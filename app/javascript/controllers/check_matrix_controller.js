import { Controller } from "@hotwired/stimulus"

// A grid of checkboxes (rows × columns, rows in groups) with smart controls:
// a whole column, a column within a group, a whole row, everything, nothing,
// or back to the usual (each box's data-usual). Each control box shows
// whether all, some or none of its boxes are ticked. Nothing saves until the
// form does. (Ticketing settings → Notifications.)
export default class extends Controller {
    static targets = ["box", "column", "groupColumn", "row"]

    connect() {
        this.refresh()
    }

    // A box changed by hand.
    changed() {
        this.refresh()
    }

    toggleColumn(event) {
        this.set(this.boxes({ col: event.target.dataset.col }), event.target.checked)
    }

    toggleGroupColumn(event) {
        this.set(this.boxes({ col: event.target.dataset.col, group: event.target.dataset.group }), event.target.checked)
    }

    toggleRow(event) {
        this.set(this.boxes({ row: event.target.dataset.row }), event.target.checked)
    }

    all(event) {
        event.preventDefault()
        this.set(this.boxTargets, true)
    }

    none(event) {
        event.preventDefault()
        this.set(this.boxTargets, false)
    }

    usual(event) {
        event.preventDefault()
        this.boxTargets.forEach((box) => { box.checked = box.dataset.usual === "true" })
        this.refresh()
    }

    // private

    boxes({ col, row, group }) {
        return this.boxTargets.filter((box) =>
            (col === undefined || box.dataset.col === col) &&
            (row === undefined || box.dataset.row === row) &&
            (group === undefined || box.dataset.group === group))
    }

    set(boxes, checked) {
        boxes.forEach((box) => { box.checked = checked })
        this.refresh()
    }

    // Each control reads its boxes: all ticked, some (the dash), or none.
    refresh() {
        const show = (control, boxes) => {
            const ticked = boxes.filter((box) => box.checked).length
            control.checked = boxes.length > 0 && ticked === boxes.length
            control.indeterminate = ticked > 0 && ticked < boxes.length
        }
        this.columnTargets.forEach((c) => show(c, this.boxes({ col: c.dataset.col })))
        this.groupColumnTargets.forEach((c) => show(c, this.boxes({ col: c.dataset.col, group: c.dataset.group })))
        this.rowTargets.forEach((c) => show(c, this.boxes({ row: c.dataset.row })))
    }
}
