import { Controller } from "@hotwired/stimulus"

// Pages through server-rendered months a few at a time: the scheduling week
// calendar shows two side by side, the phone's jump sheet one. Every month in
// reach is already on the page, so paging is only showing and hiding.
export default class extends Controller {
    static targets = ["month", "prev", "next"]
    static values = { index: Number, perPage: { type: Number, default: 1 } }

    connect() {
        this.render()
    }

    prev(event) {
        event?.preventDefault()
        event?.stopPropagation()
        this.indexValue = Math.max(0, this.indexValue - 1)
    }

    next(event) {
        event?.preventDefault()
        event?.stopPropagation()
        this.indexValue = Math.min(this.monthTargets.length - this.perPageValue, this.indexValue + 1)
    }

    indexValueChanged() {
        this.render()
    }

    render() {
        this.monthTargets.forEach((month, i) => {
            const shown = i >= this.indexValue && i < this.indexValue + this.perPageValue
            month.style.display = shown ? "" : "none"
        })
        this.prevTargets.forEach(b => { b.disabled = this.indexValue <= 0 })
        this.nextTargets.forEach(b => { b.disabled = this.indexValue >= this.monthTargets.length - this.perPageValue })
    }
}
