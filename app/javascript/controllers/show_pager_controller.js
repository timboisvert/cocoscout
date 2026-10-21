import { Controller } from "@hotwired/stimulus"

// One show at a time on a phone (V1.1 plan §4, show pager): Previous and
// Next move along the pages, and a swipe does the same.
export default class extends Controller {
    static targets = ["page", "prev", "next", "label"]

    connect() {
        this.index = Math.max(0, this.pageTargets.findIndex(p => !p.classList.contains("hidden")))
        this.element.addEventListener("touchstart", this.touchStart = this.touchStart.bind(this), { passive: true })
        this.element.addEventListener("touchend", this.touchEnd = this.touchEnd.bind(this), { passive: true })
        this.render()
    }

    disconnect() {
        this.element.removeEventListener("touchstart", this.touchStart)
        this.element.removeEventListener("touchend", this.touchEnd)
    }

    prev() { this.go(this.index - 1) }

    next() { this.go(this.index + 1) }

    go(index) {
        if (index < 0 || index >= this.pageTargets.length) return
        this.index = index
        this.render()
        window.scrollTo({ top: 0 })
    }

    render() {
        this.pageTargets.forEach((page, i) => page.classList.toggle("hidden", i !== this.index))
        if (this.hasPrevTarget) this.prevTarget.disabled = this.index === 0
        if (this.hasNextTarget) this.nextTarget.disabled = this.index >= this.pageTargets.length - 1
        if (this.hasLabelTarget) this.labelTarget.textContent = `Show ${this.index + 1} of ${this.pageTargets.length}`
    }

    touchStart(event) {
        const t = event.changedTouches[0]
        this.origin = { x: t.clientX, y: t.clientY }
    }

    touchEnd(event) {
        if (!this.origin) return
        const t = event.changedTouches[0]
        const dx = t.clientX - this.origin.x
        const dy = t.clientY - this.origin.y
        this.origin = null
        if (Math.abs(dx) < 60 || Math.abs(dx) < Math.abs(dy) * 2) return
        navigator.vibrate?.(10)
        this.go(this.index + (dx < 0 ? 1 : -1))
    }
}
