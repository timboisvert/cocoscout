import { Controller } from "@hotwired/stimulus"

// A row that scrolls sideways with no scrollbar (shared/_section_tiles, the
// one-line filters): an arrow on the right while there's more that way, one
// on the left once you've moved, neither at the ends (Tim, 2026-10-21). A
// tap on an arrow slides most of a width.
export default class extends Controller {
    static targets = ["track", "left", "right"]

    connect() {
        this.update = this.update.bind(this)
        this.trackTarget.addEventListener("scroll", this.update, { passive: true })
        window.addEventListener("resize", this.update)
        // Fonts and images settle after connect; look again once they have.
        this.update()
        requestAnimationFrame(this.update)
        setTimeout(this.update, 300)
    }

    disconnect() {
        this.trackTarget.removeEventListener("scroll", this.update)
        window.removeEventListener("resize", this.update)
    }

    update() {
        const track = this.trackTarget
        const max = track.scrollWidth - track.clientWidth
        const at = track.scrollLeft
        if (this.hasLeftTarget) this.leftTarget.classList.toggle("hidden", at <= 2)
        if (this.hasRightTarget) this.rightTarget.classList.toggle("hidden", max <= 2 || at >= max - 2)
    }

    scrollLeft() { this.slide(-1) }
    scrollRight() { this.slide(1) }

    slide(direction) {
        const track = this.trackTarget
        track.scrollBy({ left: direction * Math.max(120, track.clientWidth * 0.8), behavior: "smooth" })
    }
}
