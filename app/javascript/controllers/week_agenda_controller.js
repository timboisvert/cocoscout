import { Controller } from "@hotwired/stimulus"

// Phone: the staffing week as a strip of days with one day's shifts under it
// (V1.1 plan §4, "Day agenda + swipeable week strip"). Desktop shows every
// day: the strip is sm:hidden and the other days only hide under sm.
//
// Every scheduling action morphs the page in place and comes back to the
// day's anchor (#day-<iso>), so the chosen day survives a morph: it's kept
// here and re-applied after each one.
export default class extends Controller {
    static targets = ["day", "row"]

    connect() {
        this.reapply = this.reapply.bind(this)
        document.addEventListener("turbo:morph", this.reapply)
        this.reapply()
    }

    disconnect() {
        document.removeEventListener("turbo:morph", this.reapply)
    }

    reapply() {
        const days = this.openDays()
        if (!days.length) return
        const hash = window.location.hash
        const fromHash = hash.startsWith("#day-") ? hash.slice(5) : null
        const today = this.todayIso()
        const wanted = (this.selected && days.includes(this.selected)) ? this.selected
            : (fromHash && days.includes(fromHash)) ? fromHash
            : days.includes(today) ? today
            : days[0]
        this.select(wanted)
    }

    pick(event) {
        this.go(event.currentTarget.dataset.day)
    }

    go(iso) {
        this.select(iso)
        history.replaceState(null, "", `#day-${iso}`)
    }

    select(iso) {
        this.selected = iso
        this.dayTargets.forEach(button => {
            const on = button.dataset.day === iso
            const off = !on && !button.disabled
            button.classList.toggle("border-pink-500", on)
            button.classList.toggle("bg-pink-50", on)
            button.classList.toggle("text-pink-700", on)
            button.classList.toggle("border-gray-200", off)
            button.classList.toggle("bg-white", off)
            button.classList.toggle("text-gray-900", off)
            button.setAttribute("aria-pressed", on ? "true" : "false")
        })
        this.rowTargets.forEach(row => row.classList.toggle("max-sm:hidden", row.dataset.day !== iso))
    }

    // Swipe left for the next day with something on it, right for the one before.
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
        const days = this.openDays()
        const next = days[days.indexOf(this.selected) + (dx < 0 ? 1 : -1)]
        if (!next) return
        navigator.vibrate?.(10)
        this.go(next)
        window.scrollTo({ top: 0 })
    }

    openDays() {
        return this.dayTargets.filter(button => !button.disabled).map(button => button.dataset.day)
    }

    todayIso() {
        const d = new Date()
        const pad = n => String(n).padStart(2, "0")
        return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
    }
}
