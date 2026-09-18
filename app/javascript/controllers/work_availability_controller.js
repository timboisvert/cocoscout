import { Controller } from "@hotwired/stimulus"

// The staff Work Availability page. Everything saved goes through ordinary
// forms that post and come straight back to the page (morphed, scroll kept),
// so nothing here is optimistic: what's on screen after a save is what the
// server has. This controller only fills and opens the two sheets, runs the
// time-of-day chips, and steps the calendar between months.
export default class extends Controller {
    static targets = ["weekSheet", "exceptionSheet", "month"]

    connect() {
        this.monthIndex = 0
        this.windowCounter = 0
        this.reapplyMonth = () => this.showMonth(this.monthIndex)
        document.addEventListener("turbo:morph", this.reapplyMonth)
    }

    disconnect() {
        document.removeEventListener("turbo:morph", this.reapplyMonth)
    }

    // ----- usual week -----

    editDay(event) {
        if (event.type === "keydown") event.preventDefault()
        const row = event.currentTarget
        const sheet = this.weekSheetTarget
        this.setTitle(sheet, row.dataset.dayName)
        sheet.querySelectorAll("[data-day-name]").forEach(el => { el.textContent = row.dataset.dayName })
        sheet.querySelectorAll("[data-day-checkbox]").forEach(box => { box.checked = box.value === row.dataset.wday })
        this.fillAnswer(sheet, row.dataset.state, this.parse(row.dataset.windows))
        this.open(sheet)
    }

    // ----- exceptions -----

    addException(event, date = "") {
        if (event && event.preventDefault) event.preventDefault()
        const sheet = this.exceptionSheetTarget
        this.setTitle(sheet, "Add an exception")
        this.field(sheet, "[data-starts-on]").value = date
        this.field(sheet, "[data-ends-on]").value = date
        this.field(sheet, "[data-replacing-starts-on]").value = ""
        this.field(sheet, "[data-replacing-ends-on]").value = ""
        this.field(sheet, "[data-note]").value = ""
        // The usual reason for an exception is a day they can't do.
        this.fillAnswer(sheet, "off", [])
        this.open(sheet)
    }

    editException(event) {
        if (event.type === "keydown") event.preventDefault()
        this.openException(event.currentTarget.dataset)
    }

    // A day on the calendar: open the exception already covering it, or start
    // a new one on it.
    pickDay(event) {
        if (event.type === "keydown") event.preventDefault()
        const date = event.currentTarget.dataset.date
        const existing = [...this.element.querySelectorAll("[data-action*='editException'][data-starts-on]")]
            .find(el => el.dataset.startsOn <= date && el.dataset.endsOn >= date)
        existing ? this.openException(existing.dataset) : this.addException(null, date)
    }

    openException(data) {
        const sheet = this.exceptionSheetTarget
        this.setTitle(sheet, "Change this exception")
        this.field(sheet, "[data-starts-on]").value = data.startsOn
        this.field(sheet, "[data-ends-on]").value = data.endsOn
        this.field(sheet, "[data-replacing-starts-on]").value = data.startsOn
        this.field(sheet, "[data-replacing-ends-on]").value = data.endsOn
        this.field(sheet, "[data-note]").value = data.note || ""
        this.fillAnswer(sheet, data.state, this.parse(data.windows))
        this.open(sheet)
    }

    // Keep "Through" from sitting before "From".
    startChanged(event) {
        const sheet = event.currentTarget.closest("[data-sheet]")
        const ends = this.field(sheet, "[data-ends-on]")
        const starts = event.currentTarget.value
        ends.min = starts || ends.min
        if (!ends.value || ends.value < starts) ends.value = starts
    }

    // ----- the three answers, the chips and the windows -----

    stateChanged(event) {
        const sheet = event.currentTarget.closest("[data-sheet]")
        this.syncHours(sheet)
        if (this.stateOf(sheet) === "hours" && this.rows(sheet).length === 0) this.appendWindow(sheet)
    }

    // A chip writes its hours into the fields — into the only window, or the
    // first empty one, or a new one — and the fields flash so it's clear the
    // chip and the fields are the same thing.
    applyChip(event) {
        event.preventDefault()
        const sheet = event.currentTarget.closest("[data-sheet]")
        const from = this.clock(event.currentTarget.dataset.from)
        const to = this.clock(event.currentTarget.dataset.to)
        const rows = this.rows(sheet)
        let row = rows.length === 1 ? rows[0] : rows.find(r => !r.querySelector("[data-window-from]").value && !r.querySelector("[data-window-to]").value)
        if (!row) row = this.appendWindow(sheet)

        const fromInput = row.querySelector("[data-window-from]")
        const toInput = row.querySelector("[data-window-to]")
        fromInput.value = from
        toInput.value = to
        ;[fromInput, toInput].forEach(input => {
            input.classList.add("ring-2", "ring-pink-400")
            setTimeout(() => input.classList.remove("ring-2", "ring-pink-400"), 600)
        })
        this.clearError(sheet)
    }

    addWindow(event) {
        event.preventDefault()
        const row = this.appendWindow(event.currentTarget.closest("[data-sheet]"))
        row.querySelector("[data-window-from]").focus()
    }

    removeWindow(event) {
        event.preventDefault()
        const sheet = event.currentTarget.closest("[data-sheet]")
        event.currentTarget.closest("[data-window-row]").remove()
        if (this.rows(sheet).length === 0) this.appendWindow(sheet)
    }

    // Catch what the server would refuse before it's sent, and say so beside
    // the fields instead of closing the sheet on a failure.
    validate(event) {
        const sheet = event.currentTarget.closest("[data-sheet]")
        if (this.stateOf(sheet) !== "hours") return

        const windows = this.rows(sheet).map(r => [r.querySelector("[data-window-from]").value, r.querySelector("[data-window-to]").value])
        const filled = windows.filter(([a, b]) => a || b)
        let message = null
        if (filled.length === 0) message = "Add the hours you can work, or choose Not at all."
        else if (filled.some(([a, b]) => !a || !b)) message = "Give every window a start and an end time."
        else if (filled.some(([a, b]) => a === b && a !== "00:00")) message = "A window needs an end time after its start."

        if (message) {
            event.preventDefault()
            const error = sheet.querySelector("[data-hours-error]")
            error.textContent = message
            error.classList.remove("hidden")
        }
    }

    // ----- calendar -----

    prevMonth(event) { event.preventDefault(); this.showMonth(this.monthIndex - 1) }
    nextMonth(event) { event.preventDefault(); this.showMonth(this.monthIndex + 1) }

    showMonth(index) {
        const months = this.monthTargets
        if (months.length === 0) return
        this.monthIndex = Math.max(0, Math.min(index, months.length - 1))
        months.forEach((m, i) => m.classList.toggle("hidden", i !== this.monthIndex))
    }

    // ----- sheets -----

    open(sheet) {
        this.clearError(sheet)
        sheet.classList.remove("hidden")
    }

    closeSheets(event) {
        if (event && event.type !== "keydown") event.preventDefault()
        ;[this.weekSheetTarget, this.exceptionSheetTarget].forEach(s => s.classList.add("hidden"))
    }

    fillAnswer(sheet, state, windows) {
        sheet.querySelectorAll("input[name='state']").forEach(radio => { radio.checked = radio.value === state })
        this.rows(sheet).forEach(r => r.remove())
        ;(windows || []).forEach(w => {
            const row = this.appendWindow(sheet)
            row.querySelector("[data-window-from]").value = w.from
            row.querySelector("[data-window-to]").value = w.to
        })
        if (state === "hours" && this.rows(sheet).length === 0) this.appendWindow(sheet)
        this.syncHours(sheet)
    }

    // The hours panel shows only for "Only certain hours", and its fields are
    // only sent then.
    syncHours(sheet) {
        const on = this.stateOf(sheet) === "hours"
        const panel = sheet.querySelector("[data-hours]")
        panel.classList.toggle("hidden", !on)
        panel.querySelectorAll("[data-windows] input").forEach(input => { input.disabled = !on })
        this.clearError(sheet)
    }

    appendWindow(sheet) {
        const template = sheet.querySelector("[data-window-template]")
        const index = this.windowCounter++
        const html = template.innerHTML.replaceAll("__INDEX__", index)
        const holder = document.createElement("div")
        holder.innerHTML = html.trim()
        const row = holder.firstElementChild
        sheet.querySelector("[data-windows]").appendChild(row)
        return row
    }

    rows(sheet) { return [...sheet.querySelectorAll("[data-windows] [data-window-row]")] }

    stateOf(sheet) {
        const checked = sheet.querySelector("input[name='state']:checked")
        return checked ? checked.value : null
    }

    clearError(sheet) {
        const error = sheet.querySelector("[data-hours-error]")
        if (error) { error.textContent = ""; error.classList.add("hidden") }
    }

    setTitle(sheet, text) {
        const title = sheet.querySelector("[data-sheet-title]")
        if (title) title.textContent = text
    }

    field(sheet, selector) { return sheet.querySelector(selector) }

    // A time field has no 24:00; midnight is 00:00 (and an end at or before
    // its start runs past midnight).
    clock(value) { return value === "24:00" ? "00:00" : (value || "") }

    parse(json) {
        try { return JSON.parse(json || "[]") } catch (_) { return [] }
    }
}
