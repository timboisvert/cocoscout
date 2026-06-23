import { Controller } from "@hotwired/stimulus"

// Shows a rich cast-list popover on hover. The panel is promoted to
// position:fixed so it escapes the day card's `overflow-hidden` (which
// otherwise clips it against the top of the day). Pure-CSS group-hover
// couldn't escape that clipping context.
export default class extends Controller {
    static targets = ["panel"]

    connect() {
        this._show = this._show.bind(this)
        this._hide = this._hide.bind(this)
        this.element.addEventListener("mouseenter", this._show)
        this.element.addEventListener("mouseleave", this._hide)
    }

    disconnect() {
        this.element.removeEventListener("mouseenter", this._show)
        this.element.removeEventListener("mouseleave", this._hide)
    }

    _show() {
        if (!this.hasPanelTarget) return
        const panel = this.panelTarget
        panel.style.position = "fixed"
        panel.classList.remove("invisible", "opacity-0", "absolute", "bottom-full", "left-0", "mb-1")
        panel.classList.add("visible", "opacity-100")

        const trigger = this.element.getBoundingClientRect()
        // Measure now that it's visible.
        const rect = panel.getBoundingClientRect()
        const gap = 6

        // Prefer above the trigger; flip below if it would clip the top.
        let top = trigger.top - rect.height - gap
        if (top < 8) top = trigger.bottom + gap

        // Left-align to the trigger, clamped to the viewport.
        let left = trigger.left
        const maxLeft = window.innerWidth - rect.width - 8
        if (left > maxLeft) left = maxLeft
        if (left < 8) left = 8

        panel.style.top = `${top}px`
        panel.style.left = `${left}px`
    }

    _hide() {
        if (!this.hasPanelTarget) return
        const panel = this.panelTarget
        panel.classList.add("invisible", "opacity-0")
        panel.classList.remove("visible", "opacity-100")
    }
}
