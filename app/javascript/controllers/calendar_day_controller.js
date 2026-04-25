import { Controller } from "@hotwired/stimulus"

// Opens a daily-view modal when a calendar date is clicked.
// Expects data-calendar-day-events-value to be a JSON array of event objects.
export default class extends Controller {
    static values = {
        date: String,
        events: Array
    }

    open(event) {
        // Don't open if clicking directly on an event link
        if (event.target.closest("a")) return
        event.stopPropagation()

        this._removeModal()

        const dateLabel = this._formatDate(this.dateValue)
        const events = this.eventsValue

        const backdrop = document.createElement("div")
        backdrop.className = "fixed inset-0 z-50 flex items-center justify-center p-4"

        const HOUR_HEIGHT = 48 // px per hour
        const DAY_START_HOUR = events.length ? Math.max(0, Math.min(...events.map(e => e.hour)) - 1) : 8
        const DAY_END_HOUR = events.length ? Math.min(24, Math.max(...events.map(e => e.hour)) + 2) : 22
        const totalHours = DAY_END_HOUR - DAY_START_HOUR
        const timelineHeight = totalHours * HOUR_HEIGHT

        // Build hour grid
        const hourLines = []
        for (let h = DAY_START_HOUR; h < DAY_END_HOUR; h++) {
            const label = h === 0 ? "12am" : h < 12 ? `${h}am` : h === 12 ? "12pm" : `${h - 12}pm`
            const top = (h - DAY_START_HOUR) * HOUR_HEIGHT
            hourLines.push(`
                <div class="absolute w-full" style="top:${top}px">
                    <span class="absolute -top-2 left-0 text-[10px] text-gray-400 w-10 text-right pr-1 select-none">${label}</span>
                    <div class="absolute left-12 right-0 border-t border-gray-100"></div>
                </div>
            `)
        }

        // Group overlapping events into columns
        const columns = this._assignColumns(events)
        const totalCols = columns.length ? Math.max(...columns.map(c => c.col)) + 1 : 1

        const eventBlocks = columns.map(event => {
            const top = (event.hour + event.minute / 60 - DAY_START_HOUR) * HOUR_HEIGHT
            const height = Math.max(HOUR_HEIGHT * 1.5, event.durationHours * HOUR_HEIGHT)
            const colWidth = `calc((100% - 3rem) / ${totalCols})`
            const left = `calc(3rem + ${event.col} * (100% - 3rem) / ${totalCols})`
            const colorClass = this._colorClass(event.color, event.canceled)

            return `
                <a href="${event.path}" class="absolute rounded border text-xs px-1.5 py-1 overflow-hidden leading-snug hover:z-10 transition-shadow hover:shadow-md ${colorClass} ${event.canceled ? "opacity-60" : ""}"
                   style="top:${top}px; height:${height}px; left:${left}; width:${colWidth}; min-width:0">
                    <div class="font-semibold truncate ${event.canceled ? "line-through" : ""}">${event.time}</div>
                    <div class="truncate ${event.canceled ? "line-through" : ""}">${this._escapeHtml(event.title)}</div>
                    ${event.canceled ? '<div class="text-red-600 font-semibold text-[10px]">Canceled</div>' : ""}
                </a>
            `
        })

        backdrop.innerHTML = `
            <div class="absolute inset-0 bg-black/40" data-close></div>
            <div class="relative bg-white rounded-xl shadow-xl w-full max-w-md flex flex-col max-h-[85vh]">
                <div class="flex items-center justify-between px-4 py-3 border-b border-gray-100 flex-shrink-0">
                    <h3 class="font-semibold text-gray-900">${dateLabel}</h3>
                    <button data-close class="text-gray-400 hover:text-gray-600 p-1 rounded">
                        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12"/>
                        </svg>
                    </button>
                </div>
                <div class="overflow-y-auto flex-1 p-4">
                    ${events.length === 0
                        ? '<p class="text-sm text-gray-400 text-center py-8">No events this day.</p>'
                        : `<div class="relative" style="height:${timelineHeight}px">
                                ${hourLines.join("")}
                                ${eventBlocks.join("")}
                           </div>`
                    }
                </div>
            </div>
        `

        backdrop.addEventListener("click", (e) => {
            if (e.target.closest("[data-close]")) this._removeModal()
        })

        document.body.appendChild(backdrop)
        this._modal = backdrop
    }

    _removeModal() {
        if (this._modal) { this._modal.remove(); this._modal = null }
    }

    _assignColumns(events) {
        // Greedy column assignment to avoid overlap
        const cols = []
        return events.map(event => {
            const endH = event.hour + event.minute / 60 + event.durationHours
            let col = 0
            while (cols[col] && cols[col] > event.hour + event.minute / 60) col++
            cols[col] = endH
            return { ...event, col }
        })
    }

    _colorClass(color, canceled) {
        if (canceled) return "bg-gray-100 text-gray-500 border-gray-200"
        switch (color) {
            case "pink":   return "bg-pink-100 text-pink-800 border-pink-300"
            case "blue":   return "bg-blue-100 text-blue-800 border-blue-300"
            case "green":  return "bg-green-100 text-green-800 border-green-300"
            case "amber":  return "bg-amber-100 text-amber-800 border-amber-300"
            case "purple": return "bg-purple-100 text-purple-800 border-purple-300"
            default:       return "bg-gray-100 text-gray-800 border-gray-300"
        }
    }

    _formatDate(dateStr) {
        const d = new Date(dateStr + "T12:00:00")
        return d.toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric" })
    }

    _escapeHtml(str) {
        return String(str)
            .replace(/&/g, "&amp;").replace(/</g, "&lt;")
            .replace(/>/g, "&gt;").replace(/"/g, "&quot;")
    }
}
