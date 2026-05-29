import { Controller } from "@hotwired/stimulus"

// Modal for splitting a shift into N segments. Each segment is shown as a
// dual-handle range slider over the original shift's time range, so the user
// can drag a start/end handle directly to set that segment's times. Segments
// default to non-overlapping equal slices and snap to 5-minute increments.
//
// The form submits a segments[] array with starts_at/ends_at for each segment.
// The server replaces the original shift with these.
export default class extends Controller {
    static targets = ["modal", "form", "title", "subtitle", "countDisplay", "segmentsContainer"]
    static values = { splitUrlTemplate: String }

    open(event) {
        if (event) event.preventDefault()
        const btn = event.currentTarget
        this.shiftId = btn.dataset.shiftId
        this.originalStart = new Date(btn.dataset.shiftStartsAt)
        this.originalEnd = new Date(btn.dataset.shiftEndsAt)
        const roleName = btn.dataset.shiftRoleName || "shift"
        const timeRange = btn.dataset.shiftTimeRange || ""

        if (this.hasTitleTarget) this.titleTarget.textContent = `Split ${roleName} shift`
        if (this.hasSubtitleTarget) this.subtitleTarget.textContent = timeRange

        this.count = 2
        if (this.hasFormTarget && this.hasSplitUrlTemplateValue) {
            this.formTarget.action = this.splitUrlTemplateValue.replace(":id", this.shiftId)
        }
        this.redistribute()
        this.show()
    }

    close(event) { if (event) event.preventDefault(); this.hide() }
    backdropClose(event) { if (event.target === this.modalTarget) this.hide() }
    stopPropagation(event) { event.stopPropagation() }

    increment(event) {
        if (event) event.preventDefault()
        if (this.count < 10) { this.count++; this.redistribute() }
    }

    decrement(event) {
        if (event) event.preventDefault()
        if (this.count > 2) { this.count--; this.redistribute() }
    }

    // Reset to evenly-spaced, non-overlapping segments.
    redistribute() {
        if (!this.originalStart || !this.originalEnd) return
        if (this.hasCountDisplayTarget) this.countDisplayTarget.textContent = String(this.count)

        const totalMin = this.totalMinutes()
        const segMin = totalMin / this.count
        this.segments = []
        for (let i = 0; i < this.count; i++) {
            // Snap to 5-min increments. Last segment locks to the original end.
            const startMin = i === 0 ? 0 : Math.round((i * segMin) / 5) * 5
            const endMin = i === this.count - 1 ? totalMin : Math.round(((i + 1) * segMin) / 5) * 5
            this.segments.push({ startMin, endMin })
        }
        this.renderSegments()
    }

    renderSegments() {
        if (!this.hasSegmentsContainerTarget) return
        const totalMin = this.totalMinutes()
        const rows = this.segments.map((seg, idx) => `
            <div class="segment-row" data-index="${idx}">
                <div class="flex items-center justify-between text-xs mb-1.5">
                    <span class="font-medium text-gray-700">Segment ${idx + 1}</span>
                    <span class="text-gray-600 tabular-nums">
                        <span data-role="start-label">${this.fmt(seg.startMin)}</span>
                        <span class="text-gray-400 mx-1">→</span>
                        <span data-role="end-label">${this.fmt(seg.endMin)}</span>
                        <span class="text-gray-400 ml-1.5" data-role="duration-label">(${this.duration(seg.endMin - seg.startMin)})</span>
                    </span>
                </div>
                <div class="dual-range relative h-6 select-none">
                    <div class="absolute top-1/2 left-0 right-0 h-1.5 -mt-[3px] bg-gray-200 rounded-full pointer-events-none"></div>
                    <div class="absolute top-1/2 h-1.5 -mt-[3px] bg-pink-400 rounded-full pointer-events-none" data-role="fill"
                         style="left: ${(seg.startMin / totalMin) * 100}%; right: ${100 - (seg.endMin / totalMin) * 100}%;"></div>
                    <input type="range" min="0" max="${totalMin}" step="5" value="${seg.startMin}"
                           data-role="start" class="dual-range-input">
                    <input type="range" min="0" max="${totalMin}" step="5" value="${seg.endMin}"
                           data-role="end" class="dual-range-input">
                </div>
                <input type="hidden" name="segments[][starts_at]" data-role="start-hidden" value="${this.toLocalInputValue(seg.startMin)}">
                <input type="hidden" name="segments[][ends_at]"   data-role="end-hidden"   value="${this.toLocalInputValue(seg.endMin)}">
            </div>
        `).join("")
        this.segmentsContainerTarget.innerHTML = rows

        this.segmentsContainerTarget.querySelectorAll(".segment-row").forEach((row) => {
            const idx = parseInt(row.dataset.index, 10)
            const startInput = row.querySelector('[data-role="start"]')
            const endInput = row.querySelector('[data-role="end"]')
            startInput.addEventListener("input", () => this.handleSliderChange(idx, row, "start"))
            endInput.addEventListener("input", () => this.handleSliderChange(idx, row, "end"))
        })
    }

    handleSliderChange(idx, row, which) {
        const totalMin = this.totalMinutes()
        const startInput = row.querySelector('[data-role="start"]')
        const endInput = row.querySelector('[data-role="end"]')
        let s = parseInt(startInput.value, 10)
        let e = parseInt(endInput.value, 10)

        // Keep at least a 5-min gap; push the un-grabbed handle out of the way.
        if (s >= e) {
            if (which === "start") {
                s = Math.max(0, e - 5)
                startInput.value = s
            } else {
                e = Math.min(totalMin, s + 5)
                endInput.value = e
            }
        }

        this.segments[idx] = { startMin: s, endMin: e }

        row.querySelector('[data-role="start-label"]').textContent = this.fmt(s)
        row.querySelector('[data-role="end-label"]').textContent = this.fmt(e)
        row.querySelector('[data-role="duration-label"]').textContent = `(${this.duration(e - s)})`

        const fill = row.querySelector('[data-role="fill"]')
        fill.style.left = `${(s / totalMin) * 100}%`
        fill.style.right = `${100 - (e / totalMin) * 100}%`

        row.querySelector('[data-role="start-hidden"]').value = this.toLocalInputValue(s)
        row.querySelector('[data-role="end-hidden"]').value = this.toLocalInputValue(e)
    }

    totalMinutes() {
        return Math.round((this.originalEnd - this.originalStart) / 60000)
    }

    fmt(minutesFromStart) {
        const d = new Date(this.originalStart.getTime() + minutesFromStart * 60000)
        let h = d.getHours()
        const m = d.getMinutes()
        const ampm = h >= 12 ? "PM" : "AM"
        h = h % 12 || 12
        return `${h}:${String(m).padStart(2, "0")} ${ampm}`
    }

    duration(minutes) {
        if (minutes < 60) return `${minutes}m`
        const h = Math.floor(minutes / 60)
        const m = minutes % 60
        return m === 0 ? `${h}h` : `${h}h ${m}m`
    }

    toLocalInputValue(minutesFromStart) {
        const d = new Date(this.originalStart.getTime() + minutesFromStart * 60000)
        const pad = n => String(n).padStart(2, "0")
        return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
    }

    show() { if (this.hasModalTarget) this.modalTarget.classList.remove("hidden") }
    hide() { if (this.hasModalTarget) this.modalTarget.classList.add("hidden") }
}
