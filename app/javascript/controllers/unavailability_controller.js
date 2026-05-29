import { Controller } from "@hotwired/stimulus"

// Fully client-side availability calendar for My Shifts. Renders the summary
// and a month grid, navigates months without a server round-trip, and supports
// single-day or multi-day selection. Changes persist via fetch (JSON) and are
// applied optimistically to local state.
const SCOPE_LABEL = { all_day: "All day", day_shifts: "Afternoon", evening_shifts: "Evening" }
const SCOPE_CELL = {
    all_day: "bg-red-100 border-red-300 text-red-800",
    day_shifts: "bg-amber-100 border-amber-300 text-amber-800",
    evening_shifts: "bg-indigo-100 border-indigo-300 text-indigo-800"
}

export default class extends Controller {
    static targets = ["summary", "modal", "calendar", "monthLabel", "actionBar", "selectedCount", "multiButton"]
    static values = { entries: Array, createUrl: String }

    connect() {
        this.entries = new Map((this.entriesValue || []).map(e => [e.date, e.scope]))
        this.viewMonth = this.startOfMonth(new Date())
        this.multiMode = false
        this.selected = new Set()
        this.renderSummary()
    }

    open(event) {
        if (event) event.preventDefault()
        this.viewMonth = this.startOfMonth(new Date())
        this.multiMode = false
        this.selected.clear()
        this.renderCalendar()
        if (this.hasModalTarget) this.modalTarget.classList.remove("hidden")
    }

    close(event) {
        if (event) event.preventDefault()
        if (this.hasModalTarget) this.modalTarget.classList.add("hidden")
    }

    backdropClose(event) { if (event.target === this.modalTarget) this.close() }
    stopPropagation(event) { event.stopPropagation() }

    prevMonth(event) { if (event) event.preventDefault(); this.viewMonth = this.addMonths(this.viewMonth, -1); this.renderCalendar() }
    nextMonth(event) { if (event) event.preventDefault(); this.viewMonth = this.addMonths(this.viewMonth, 1); this.renderCalendar() }

    toggleMulti(event) {
        if (event) event.preventDefault()
        this.multiMode = !this.multiMode
        this.selected.clear()
        this.renderCalendar()
    }

    dayClick(event) {
        const ds = event.currentTarget.dataset.date
        if (!ds || this.isPast(ds)) return
        if (this.multiMode) {
            this.selected.has(ds) ? this.selected.delete(ds) : this.selected.add(ds)
        } else if (this.selected.has(ds) && this.selected.size === 1) {
            this.selected.clear()
        } else {
            this.selected.clear()
            this.selected.add(ds)
        }
        this.renderCalendar()
    }

    apply(event) {
        if (event) event.preventDefault()
        const scope = event.currentTarget.dataset.scope
        const dates = [...this.selected]
        if (dates.length === 0) return

        if (scope === "clear") {
            dates.forEach(d => this.entries.delete(d))
        } else {
            dates.forEach(d => this.entries.set(d, scope))
        }
        this.persist(dates, scope)

        this.selected.clear()
        this.multiMode = false
        this.renderCalendar()
        this.renderSummary()
    }

    cancelSelect(event) {
        if (event) event.preventDefault()
        this.selected.clear()
        this.renderCalendar()
    }

    persist(dates, scope) {
        const token = document.querySelector('meta[name="csrf-token"]')?.content
        fetch(this.createUrlValue, {
            method: "POST",
            headers: { "Content-Type": "application/json", "X-CSRF-Token": token, "Accept": "application/json" },
            body: JSON.stringify({ dates, scope })
        }).catch(() => {})
    }

    // ----- rendering -----

    renderSummary() {
        if (!this.hasSummaryTarget) return
        const today = this.todayStr()
        const upcoming = [...this.entries.entries()]
            .filter(([d]) => d >= today)
            .sort((a, b) => (a[0] < b[0] ? -1 : 1))

        if (upcoming.length === 0) {
            this.summaryTarget.innerHTML = `
                <div class="text-sm font-medium text-gray-900">Your availability</div>
                <div class="text-xs text-gray-500 mt-1">You're available for all upcoming shifts. Block off any days you can't work.</div>`
            return
        }

        const limit = 4
        const rows = upcoming.slice(0, limit).map(([d, scope]) => this.summaryRow(d, scope)).join("")
        let extra = ""
        if (upcoming.length > limit) {
            const peek = upcoming[limit]
            extra = `
                <div class="opacity-40">${this.summaryRow(peek[0], peek[1])}</div>
                <button type="button" data-action="click->unavailability#open"
                        class="mt-1 text-xs font-medium text-pink-600 hover:text-pink-700 cursor-pointer">
                    Show all ${upcoming.length} →
                </button>`
        }
        this.summaryTarget.innerHTML = `
            <div class="text-sm font-medium text-gray-900">Upcoming dates you're unavailable</div>
            <div class="mt-1 space-y-0.5">${rows}${extra}</div>`
    }

    summaryRow(d, scope) {
        const label = (SCOPE_LABEL[scope] || "").toLowerCase()
        return `<div class="text-xs text-gray-600"><span class="font-medium text-gray-800">${this.fmtLong(d)}</span> <span class="text-gray-400">· ${label}</span></div>`
    }

    renderCalendar() {
        if (!this.hasCalendarTarget) return
        if (this.hasMonthLabelTarget) {
            this.monthLabelTarget.textContent = this.viewMonth.toLocaleDateString(undefined, { month: "long", year: "numeric" })
        }
        const year = this.viewMonth.getFullYear()
        const month = this.viewMonth.getMonth()
        const lead = new Date(year, month, 1).getDay()
        const daysInMonth = new Date(year, month + 1, 0).getDate()

        let cells = ""
        for (let i = 0; i < lead; i++) cells += `<div></div>`
        for (let day = 1; day <= daysInMonth; day++) {
            const ds = this.fmt(new Date(year, month, day))
            const scope = this.entries.get(ds)
            const selected = this.selected.has(ds)
            const past = this.isPast(ds)
            const base = "min-h-[44px] rounded border px-1 py-1 flex flex-col items-center justify-center text-sm"
            let cls
            if (past) cls = `${base} bg-gray-50 border-gray-100 text-gray-300`
            else if (selected) cls = `${base} bg-pink-500 border-pink-500 text-white cursor-pointer`
            else if (scope) cls = `${base} ${SCOPE_CELL[scope]} cursor-pointer`
            else cls = `${base} bg-white border-gray-200 text-gray-700 hover:border-pink-300 cursor-pointer`

            const label = (!selected && scope) ? `<span class="text-[9px] leading-tight">${SCOPE_LABEL[scope]}</span>` : ""
            const action = past ? "" : `data-action="click->unavailability#dayClick" data-date="${ds}"`
            cells += `<div class="${cls}" ${action}><span class="font-medium">${day}</span>${label}</div>`
        }
        this.calendarTarget.innerHTML = cells

        if (this.hasMultiButtonTarget) {
            this.multiButtonTarget.textContent = this.multiMode ? "Done selecting" : "Select multiple days"
            this.multiButtonTarget.classList.toggle("bg-pink-100", this.multiMode)
            this.multiButtonTarget.classList.toggle("text-pink-700", this.multiMode)
        }
        this.renderActionBar()
    }

    renderActionBar() {
        if (!this.hasActionBarTarget) return
        const n = this.selected.size
        this.actionBarTarget.classList.toggle("hidden", n === 0)
        if (n === 0) return

        if (this.hasSelectedCountTarget) {
            this.selectedCountTarget.textContent = `${n} day${n === 1 ? "" : "s"} selected — mark as:`
        }
        // Pluralize Afternoon/Evening when more than one day is selected.
        const plural = n > 1
        const labels = {
            all_day: "Unavailable All Day",
            day_shifts: `Unavailable Afternoon${plural ? "s" : ""}`,
            evening_shifts: `Unavailable Evening${plural ? "s" : ""}`
        }
        this.actionBarTarget.querySelectorAll("[data-scope]").forEach(btn => {
            const label = labels[btn.dataset.scope]
            if (label) btn.textContent = label
        })
    }

    // ----- helpers -----
    startOfMonth(d) { return new Date(d.getFullYear(), d.getMonth(), 1) }
    addMonths(d, n) { return new Date(d.getFullYear(), d.getMonth() + n, 1) }
    fmt(d) { const p = n => String(n).padStart(2, "0"); return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}` }
    fmtShort(ds) { return new Date(`${ds}T12:00:00`).toLocaleDateString(undefined, { month: "short", day: "numeric" }) }
    fmtLong(ds) { return new Date(`${ds}T12:00:00`).toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" }) }
    todayStr() { return this.fmt(new Date()) }
    isPast(ds) { return ds < this.todayStr() }
}
