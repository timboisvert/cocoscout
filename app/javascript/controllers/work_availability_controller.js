import { Controller } from "@hotwired/stimulus"

// The staff Work Availability page. Everything saved goes through ordinary
// forms that post and come straight back to the page (morphed, scroll kept),
// so nothing here is optimistic: what's on screen after a save is what the
// server has. This controller only fills and opens the two sheets (my usual
// week; a date) and runs the time-of-day chips; months page by ordinary links.
export default class extends Controller {
    static targets = ["weekSheet", "dateSheet"]

    connect() {
        this.windowCounter = 0
    }

    // ----- my usual week -----

    // The button opens it fresh; a line of the usual week opens it on those
    // days with their answer.
    editWeek(event) {
        if (event.type === "keydown") event.preventDefault()
        const data = event.currentTarget.dataset
        const sheet = this.weekSheetTarget
        const wdays = this.parse(data.wdays).map(String)
        sheet.querySelectorAll("[data-day-checkbox]").forEach(box => { box.checked = wdays.includes(box.value) })
        this.fillAnswer(sheet, data.state || null, this.parse(data.windows))
        this.open(sheet)
    }

    // ----- a date -----

    // A date on the calendar: the change already covering it if there is one
    // (the cell carries it), otherwise just this date, starting from its
    // usual weekday's answer.
    editDate(event) {
        if (event.type === "keydown") event.preventDefault()
        const cell = event.currentTarget.dataset
        if (cell.changeStartsOn) {
            return this.openDateSheet({
                title: cell.changeTitle, replacing: true,
                startsOn: cell.changeStartsOn, endsOn: cell.changeEndsOn, note: cell.changeNote,
                state: cell.changeState, windows: this.parse(cell.changeWindows)
            })
        }

        this.openDateSheet({
            title: cell.title, startsOn: cell.date, endsOn: cell.date,
            state: cell.state || "anytime", windows: this.parse(cell.windows)
        })
    }

    openDateSheet(o) {
        const sheet = this.dateSheetTarget
        this.setTitle(sheet, o.title)

        // Dates can't start in the past, except a run that's already under way.
        const starts = this.field(sheet, "[data-starts-on]")
        const ends = this.field(sheet, "[data-ends-on]")
        starts.dataset.today ||= starts.min
        starts.min = o.startsOn && o.startsOn < starts.dataset.today ? o.startsOn : starts.dataset.today
        ends.min = o.startsOn || starts.min
        starts.value = o.startsOn || ""
        ends.value = o.endsOn || ""
        this.field(sheet, "[data-note]").value = o.note || ""
        this.field(sheet, "[data-replacing-starts-on]").value = o.replacing ? o.startsOn : ""
        this.field(sheet, "[data-replacing-ends-on]").value = o.replacing ? o.endsOn : ""

        // Undoing a change only means something for dates already changed.
        sheet.querySelector("[data-revert]").classList.toggle("hidden", !o.replacing)
        this.field(sheet, "[data-revert-starts-on]").value = o.replacing ? o.startsOn : ""
        this.field(sheet, "[data-revert-ends-on]").value = o.replacing ? o.endsOn : ""

        this.fillAnswer(sheet, o.state, o.windows)
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

    // A chip sets its hours in the dropdowns — in the only window, or the
    // first empty one, or a new one — and they flash so it's clear the chip
    // and the dropdowns are the same thing.
    applyChip(event) {
        event.preventDefault()
        const sheet = event.currentTarget.closest("[data-sheet]")
        const from = this.clock(event.currentTarget.dataset.from)
        const to = this.clock(event.currentTarget.dataset.to)
        const rows = this.rows(sheet)
        let row = rows.length === 1 ? rows[0] : rows.find(r => !r.querySelector("[data-window-from]").value && !r.querySelector("[data-window-to]").value)
        if (!row) row = this.appendWindow(sheet)

        this.setClock(row.querySelector("[data-window-from]"), from)
        this.setClock(row.querySelector("[data-window-to]"), to)
        row.querySelectorAll("[data-clock-part]").forEach(select => {
            select.classList.add("ring-2", "ring-pink-400")
            setTimeout(() => select.classList.remove("ring-2", "ring-pink-400"), 600)
        })
        this.clearError(sheet)
    }

    addWindow(event) {
        event.preventDefault()
        const row = this.appendWindow(event.currentTarget.closest("[data-sheet]"))
        row.querySelector("[data-clock-part='hour']").focus()
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
        const daysError = sheet.querySelector("[data-days-error]")
        if (daysError) {
            const none = !sheet.querySelector("[data-day-checkbox]:checked")
            daysError.textContent = none ? "Pick at least one day." : ""
            daysError.classList.toggle("hidden", !none)
            if (none) { event.preventDefault(); return }
        }
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

    // ----- sheets -----

    open(sheet) {
        this.clearError(sheet)
        sheet.classList.remove("hidden")
    }

    closeSheets(event) {
        if (event && event.type !== "keydown") event.preventDefault()
        ;[this.weekSheetTarget, this.dateSheetTarget].forEach(s => s.classList.add("hidden"))
    }

    // ----- the hour / minute / AM-PM dropdowns -----

    // Any dropdown changing rewrites the hidden "17:05" the form sends; with
    // no hour picked yet it sends nothing.
    clockChanged(event) {
        const clock = event.currentTarget.closest("[data-clock]")
        const part = name => clock.querySelector(`[data-clock-part='${name}']`).value
        const hidden = clock.querySelector("input[type='hidden']")
        if (!part("hour")) { hidden.value = ""; return }

        const hour = Number(part("hour")) % 12 + (part("meridiem") === "PM" ? 12 : 0)
        hidden.value = `${String(hour).padStart(2, "0")}:${String(part("minute")).padStart(2, "0")}`
        this.clearError(event.currentTarget.closest("[data-sheet]"))
    }

    // "17:05" (or "" for none) → the three dropdowns and the hidden field.
    setClock(hidden, value) {
        const clock = hidden.closest("[data-clock]")
        const set = (name, v) => { clock.querySelector(`[data-clock-part='${name}']`).value = v }
        const match = /^(\d{1,2}):(\d{2})/.exec(value || "")
        if (!match) { set("hour", ""); hidden.value = ""; return }

        const h = Number(match[1]) % 24
        const m = Number(match[2]) - Number(match[2]) % 5
        set("hour", String(h % 12 === 0 ? 12 : h % 12))
        set("minute", String(m))
        set("meridiem", h < 12 ? "AM" : "PM")
        hidden.value = `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`
    }

    fillAnswer(sheet, state, windows) {
        sheet.querySelectorAll("input[name='state']").forEach(radio => { radio.checked = radio.value === state })
        this.rows(sheet).forEach(r => r.remove())
        ;(windows || []).forEach(w => {
            const row = this.appendWindow(sheet)
            this.setClock(row.querySelector("[data-window-from]"), w.from)
            this.setClock(row.querySelector("[data-window-to]"), w.to)
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
