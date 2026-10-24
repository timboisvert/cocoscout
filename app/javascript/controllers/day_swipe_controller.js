import { Controller } from "@hotwired/stimulus"

// Phone scheduling: swipe the day left for the next day, right for the one
// before. The day strip's links do the same with a tap.
export default class extends Controller {
    static values = { prevUrl: String, nextUrl: String }

    start(event) {
        const t = event.changedTouches[0]
        this.origin = { x: t.clientX, y: t.clientY }
    }

    end(event) {
        if (!this.origin) return
        const t = event.changedTouches[0]
        const dx = t.clientX - this.origin.x
        const dy = t.clientY - this.origin.y
        this.origin = null
        if (Math.abs(dx) < 60 || Math.abs(dx) < Math.abs(dy) * 2) return
        // A swipe that started in a sideways-scrolling timeline is a scroll.
        if (event.target.closest?.("[data-day-swipe-ignore]")) return
        const url = dx < 0 ? this.nextUrlValue : this.prevUrlValue
        if (!url) return
        navigator.vibrate?.(10)
        window.Turbo ? window.Turbo.visit(url) : (window.location.href = url)
    }
}
