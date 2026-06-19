import { Controller } from "@hotwired/stimulus"

// "Generate shifts" modal: pick which shows to staff, and — when selected shows
// on a day have a 2h+ gap — split the all-evening house shift into separate
// shifts (one tied to the earlier shows, one to the later ones) using the same
// dual-handle segment sliders as the manual "Split shift" modal.
// Submits show_ids[] and split_segments[][starts_at]/[ends_at].
const TWO_HOURS_MS = 2 * 60 * 60 * 1000
const BUFFER_MIN = 60 // default coverage before the first / after the last show
const STEP = 5        // 5-minute slider snapping

export default class extends Controller {
    static targets = ["modal", "showCheckbox", "splitSection", "splitContainer"]

    open(event) { if (event) event.preventDefault(); this.recompute(); this.show() }
    close(event) { if (event) event.preventDefault(); this.hide() }
    backdropClose(event) { if (event.target === this.modalTarget) this.hide() }
    stopPropagation(event) { event.stopPropagation() }

    selectAll(event) {
        if (event) event.preventDefault()
        this.showCheckboxTargets.forEach(cb => { cb.checked = true })
        this.recompute()
    }

    selectNone(event) {
        if (event) event.preventDefault()
        this.showCheckboxTargets.forEach(cb => { cb.checked = false })
        this.recompute()
    }

    // Re-render split controls: any day whose selected shows fall into 2+
    // clusters (separated by a 2h+ gap) gets a per-shift slider group.
    recompute() {
        if (!this.hasSplitContainerTarget) return
        const byDay = {}
        this.showCheckboxTargets.forEach(cb => {
            if (!cb.checked) return
            ;(byDay[cb.dataset.showDay] ||= []).push({
                start: new Date(cb.dataset.showStart),
                end: new Date(cb.dataset.showEnd)
            })
        })

        this.splitContainerTarget.replaceChildren()
        let anyGap = false
        Object.keys(byDay).sort().forEach(day => {
            const shows = byDay[day].sort((a, b) => a.start - b.start)
            const clusters = this.clusters(shows)
            if (clusters.length < 2) return
            anyGap = true
            this.splitContainerTarget.appendChild(this.buildDayGroup(shows, clusters))
        })
        if (this.hasSplitSectionTarget) this.splitSectionTarget.classList.toggle("hidden", !anyGap)
    }

    // Split shows into clusters separated by 2h+ gaps.
    clusters(shows) {
        const groups = [[shows[0]]]
        for (let i = 1; i < shows.length; i++) {
            const prevEnd = groups[groups.length - 1][groups[groups.length - 1].length - 1].end
            if (shows[i].start - prevEnd >= TWO_HOURS_MS) groups.push([shows[i]])
            else groups[groups.length - 1].push(shows[i])
        }
        return groups
    }

    buildDayGroup(shows, clusters) {
        const spanStart = new Date(shows[0].start.getTime() - BUFFER_MIN * 60000)
        const spanEnd = new Date(shows[shows.length - 1].end.getTime() + BUFFER_MIN * 60000)
        const totalMin = Math.round((spanEnd - spanStart) / 60000)
        const toMin = d => Math.round((d - spanStart) / 60000)

        // Default each segment to its cluster ± the buffer.
        const segments = clusters.map(c => ({
            startMin: Math.max(0, toMin(new Date(c[0].start.getTime() - BUFFER_MIN * 60000))),
            endMin: Math.min(totalMin, toMin(new Date(c[c.length - 1].end.getTime() + BUFFER_MIN * 60000)))
        }))

        const group = document.createElement("div")
        group.className = "rounded-lg border border-gray-200 bg-gray-50 p-3"
        group.dataset.spanStart = String(spanStart.getTime())

        const head = document.createElement("label")
        head.className = "flex items-center gap-2 text-sm text-gray-800 mb-3 cursor-pointer"
        const toggle = document.createElement("input")
        toggle.type = "checkbox"; toggle.checked = true
        toggle.className = "h-4 w-4 text-pink-600 border-gray-300 rounded focus:ring-pink-500 accent-pink-500"
        const headText = document.createElement("span")
        const dayLabel = spanStart.toLocaleDateString(undefined, { weekday: "long", month: "short", day: "numeric" })
        headText.innerHTML = `<span class="font-medium">${dayLabel}</span> — split into ${segments.length} shifts`
        head.append(toggle, headText)
        group.appendChild(head)

        const rows = document.createElement("div")
        rows.className = "space-y-3"
        segments.forEach((seg, idx) => rows.appendChild(this.buildSegmentRow(group, totalMin, seg, idx)))
        group.appendChild(rows)

        toggle.addEventListener("change", () => {
            rows.classList.toggle("opacity-40", !toggle.checked)
            rows.classList.toggle("pointer-events-none", !toggle.checked)
            group.querySelectorAll('[data-role="start-hidden"],[data-role="end-hidden"]')
                .forEach(h => { h.disabled = !toggle.checked })
        })

        return group
    }

    buildSegmentRow(group, totalMin, seg, idx) {
        const row = document.createElement("div")
        row.innerHTML = `
            <div class="flex items-center justify-between text-xs mb-1.5">
                <span class="font-medium text-gray-700">Shift ${idx + 1}</span>
                <span class="text-gray-600 tabular-nums">
                    <span data-role="start-label"></span><span class="text-gray-400 mx-1">→</span><span data-role="end-label"></span>
                    <span class="text-gray-400 ml-1.5" data-role="duration-label"></span>
                </span>
            </div>
            <div class="dual-range relative h-6 select-none">
                <div class="absolute top-1/2 left-0 right-0 h-1.5 -mt-[3px] bg-gray-200 rounded-full pointer-events-none"></div>
                <div class="absolute top-1/2 h-1.5 -mt-[3px] bg-pink-400 rounded-full pointer-events-none" data-role="fill"></div>
                <input type="range" min="0" max="${totalMin}" step="${STEP}" value="${seg.startMin}" data-role="start" class="dual-range-input">
                <input type="range" min="0" max="${totalMin}" step="${STEP}" value="${seg.endMin}" data-role="end" class="dual-range-input">
            </div>
            <input type="hidden" name="split_segments[][starts_at]" data-role="start-hidden">
            <input type="hidden" name="split_segments[][ends_at]"   data-role="end-hidden">
        `
        row.querySelector('[data-role="start"]').addEventListener("input", () => this.syncRow(group, totalMin, row, "start"))
        row.querySelector('[data-role="end"]').addEventListener("input", () => this.syncRow(group, totalMin, row, "end"))
        this.syncRow(group, totalMin, row, null)
        return row
    }

    syncRow(group, totalMin, row, which) {
        const startInput = row.querySelector('[data-role="start"]')
        const endInput = row.querySelector('[data-role="end"]')
        let s = parseInt(startInput.value, 10)
        let e = parseInt(endInput.value, 10)
        if (s >= e) {
            if (which === "start") { s = Math.max(0, e - STEP); startInput.value = s }
            else { e = Math.min(totalMin, s + STEP); endInput.value = e }
        }
        const spanStart = Number(group.dataset.spanStart)
        row.querySelector('[data-role="start-label"]').textContent = this.fmt(spanStart, s)
        row.querySelector('[data-role="end-label"]').textContent = this.fmt(spanStart, e)
        row.querySelector('[data-role="duration-label"]').textContent = `(${this.duration(e - s)})`
        const fill = row.querySelector('[data-role="fill"]')
        fill.style.left = `${(s / totalMin) * 100}%`
        fill.style.right = `${100 - (e / totalMin) * 100}%`
        row.querySelector('[data-role="start-hidden"]').value = this.toLocalInput(spanStart, s)
        row.querySelector('[data-role="end-hidden"]').value = this.toLocalInput(spanStart, e)
    }

    fmt(spanStartMs, min) {
        const d = new Date(spanStartMs + min * 60000)
        let h = d.getHours(); const m = d.getMinutes(); const ampm = h >= 12 ? "PM" : "AM"; h = h % 12 || 12
        return `${h}:${String(m).padStart(2, "0")} ${ampm}`
    }

    duration(min) {
        if (min < 60) return `${min}m`
        const h = Math.floor(min / 60); const m = min % 60
        return m === 0 ? `${h}h` : `${h}h ${m}m`
    }

    toLocalInput(spanStartMs, min) {
        const d = new Date(spanStartMs + min * 60000); const p = n => String(n).padStart(2, "0")
        return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`
    }

    show() { if (this.hasModalTarget) this.modalTarget.classList.remove("hidden") }
    hide() { if (this.hasModalTarget) this.modalTarget.classList.add("hidden") }
}
