import { Controller } from "@hotwired/stimulus"
import { dayPartsFor, entryCovers } from "controllers/lib/day_parts"

// The progressive Add-shift modal. Pick a role and the rest reveals itself
// already filled in: the suggested time window (editable), the show picker for
// per-show roles, and the qualified people so the shift can be staffed in the
// same motion. Leaving the person blank creates an unassigned shift.
//
// Shares the page root with shift-assign, so the staff pool / unavailability /
// cast payloads are read straight off the root element's shift-assign values
// rather than being serialized twice.
export default class extends Controller {
    static targets = ["modal", "form", "subtitle", "roleSelect", "details",
                      "startInput", "endInput", "startTimeInput", "endTimeInput", "timeHint",
                      "sourceTypeInput", "sourceIdInput", "showRow", "showList", "showIdsWrap",
                      "people", "personIdInput", "submitWrap"]
    static values = { createUrl: String }

    open(event) {
        if (event) event.preventDefault()
        const btn = event.currentTarget

        this.roleDefaults = this.parse(btn.dataset.roleDefaults, {}) // { roleId: {starts_at, ends_at} }
        this.showDefaults = this.parse(btn.dataset.showDefaults, {}) // { roleId: { showId: {starts_at, ends_at} } }
        this.dayShows = this.parse(btn.dataset.dayShows, [])         // [{ id, label }]
        this.defaultSourceShowId = btn.dataset.sourceShowId || ""
        this.dayIso = btn.dataset.dayIso || ""

        // Sibling controller payloads, shared via the page root.
        this.staffByRole = this.parse(this.element.dataset.shiftAssignStaffByRoleValue, {})
        this.unavailability = this.parse(this.element.dataset.shiftAssignStaffUnavailabilityValue, {})
        this.dayParts = this.parse(this.element.dataset.shiftAssignDayPartsValue, [])
        this.castByDay = this.parse(this.element.dataset.shiftAssignCastByDayValue, {})

        if (this.hasSubtitleTarget) this.subtitleTarget.textContent = btn.dataset.dayLabel || ""
        if (this.hasFormTarget && this.hasCreateUrlValue) this.formTarget.action = this.createUrlValue

        // Fresh start: no role chosen yet, everything else tucked away.
        if (this.hasRoleSelectTarget) this.roleSelectTarget.value = ""
        this.clearPerson()
        this.roleChanged()
        this.show()
    }

    // Opened from somewhere that already knows the role: a role's own column in
    // the day grid ("+ Another Bartender"), or Role Call's "Staff it", which
    // also names the show. The modal opens on that role with its window filled
    // in and its qualified people already showing.
    openForRole(event) {
        this.open(event)
        const roleId = event.currentTarget.dataset.preselectRoleId || ""
        if (this.hasRoleSelectTarget && roleId) {
            this.roleSelectTarget.value = roleId
            this.roleChanged()
        }
    }

    // Role picked: reveal the rest. Per-show roles get the show picker (which
    // drives the times); house roles get the whole-evening window.
    roleChanged() {
        if (!this.hasRoleSelectTarget) return
        const roleId = this.roleSelectTarget.value

        if (!roleId) {
            if (this.hasDetailsTarget) this.detailsTarget.classList.add("hidden")
            this.writeExtraShowIds([])
            this.setSubmitEnabled(false)
            return
        }

        if (this.hasDetailsTarget) this.detailsTarget.classList.remove("hidden")
        this.setSubmitEnabled(true)

        const perShow = this.showDefaults[roleId]
        if (perShow && this.dayShows.length) {
            this.renderShowChecklist()
            if (this.hasShowRowTarget) this.showRowTarget.classList.remove("hidden")
            this.showsChanged()
        } else {
            if (this.hasShowRowTarget) this.showRowTarget.classList.add("hidden")
            this.writeExtraShowIds([])
            const d = this.roleDefaults[roleId]
            if (d) this.applyTimes(d.starts_at, d.ends_at)
            this.setSource(this.defaultSourceShowId)
        }

        this.clearPerson()
        this.renderPeople(roleId)
    }

    // Shows checked or unchecked (per-show roles): the shift spans every
    // checked show — earliest start to latest end — anchored to the first
    // (source), with the rest submitted as extra covered shows.
    showsChanged() {
        const perShow = this.showDefaults[this.roleSelectTarget.value]
        if (!perShow) return

        const checked = this.checkedShowIds()
        if (checked.length === 0) {
            this.setSource("")
            this.writeExtraShowIds([])
            this.setSubmitEnabled(false)
            if (this.hasTimeHintTarget) this.timeHintTarget.textContent = "Check at least one show."
            return
        }
        this.setSubmitEnabled(true)

        let start = null, end = null
        checked.forEach(id => {
            const d = perShow[id]
            if (!d) return
            if (!start || d.starts_at < start) start = d.starts_at
            if (!end || d.ends_at > end) end = d.ends_at
        })
        if (start && end) this.applyTimes(start, end)

        this.setSource(checked[0])
        this.writeExtraShowIds(checked.slice(1))
    }

    renderShowChecklist() {
        if (!this.hasShowListTarget) return
        const preferred = this.defaultSourceShowId && this.dayShows.some(s => s.id === this.defaultSourceShowId)
            ? this.defaultSourceShowId
            : (this.dayShows[0] || {}).id
        this.showListTarget.innerHTML = this.dayShows.map(s => `
            <label class="flex items-center gap-2 cursor-pointer">
                <input type="checkbox" value="${this.h(s.id)}" ${s.id === preferred ? "checked" : ""}
                       data-action="change->shift-add#showsChanged"
                       class="h-4 w-4 text-pink-600 border-gray-300 rounded focus:ring-pink-500 accent-pink-500">
                <span class="text-sm text-gray-800 min-w-0 truncate">${this.h(s.label)}</span>
            </label>`).join("")
    }

    // Checked ids in DOM order — dayShows is chronological, so the first
    // checked show is the earliest and becomes the source anchor.
    checkedShowIds() {
        if (!this.hasShowListTarget) return []
        return Array.from(this.showListTarget.querySelectorAll("input[type=checkbox]:checked")).map(i => i.value)
    }

    writeExtraShowIds(ids) {
        if (!this.hasShowIdsWrapTarget) return
        this.showIdsWrapTarget.innerHTML = ids.map(id =>
            `<input type="hidden" name="shift[show_ids][]" value="${this.h(id)}">`).join("")
    }

    // Seed the visible time inputs and the hidden datetimes from a suggested
    // window ("YYYY-MM-DDTHH:MM" local).
    applyTimes(startsAt, endsAt) {
        this.baseDate = (startsAt || "").split("T")[0]
        if (this.hasStartTimeInputTarget) this.startTimeInputTarget.value = (startsAt || "").split("T")[1] || ""
        if (this.hasEndTimeInputTarget) this.endTimeInputTarget.value = (endsAt || "").split("T")[1] || ""
        this.syncHiddenTimes()
    }

    // The manager edited a time by hand — keep the hidden datetimes in step.
    timesEdited() {
        this.syncHiddenTimes()
    }

    // End time earlier than start rolls to the next day (a shift crossing
    // midnight), mirroring the edit modal's behavior.
    syncHiddenTimes() {
        if (!this.baseDate) return
        const start = this.hasStartTimeInputTarget ? this.startTimeInputTarget.value : ""
        const end = this.hasEndTimeInputTarget ? this.endTimeInputTarget.value : ""
        if (!start || !end) return

        const endDate = end <= start ? this.nextDay(this.baseDate) : this.baseDate
        if (this.hasStartInputTarget) this.startInputTarget.value = `${this.baseDate}T${start}`
        if (this.hasEndInputTarget) this.endInputTarget.value = `${endDate}T${end}`
        if (this.hasTimeHintTarget) {
            const rollover = end <= start ? " (past midnight)" : ""
            this.timeHintTarget.textContent = `Runs ${this.fmt(start)} – ${this.fmt(end)}${rollover}. Adjust as needed.`
        }
    }

    setSource(showId) {
        if (this.hasSourceTypeInputTarget) this.sourceTypeInputTarget.value = showId ? "Show" : ""
        if (this.hasSourceIdInputTarget)   this.sourceIdInputTarget.value   = showId || ""
    }

    // ----- person picker -----

    renderPeople(roleId) {
        if (!this.hasPeopleTarget) return
        const pool = this.staffByRole[roleId] || []
        if (pool.length === 0) {
            this.peopleTarget.innerHTML = `<p class="col-span-2 text-xs text-gray-400 py-2">No one is qualified for this role yet.</p>`
            return
        }

        this.peopleTarget.innerHTML = pool.map(p => {
            const badge = this.badgeFor(p.id)
            const avatar = p.headshot_url
                ? `<img src="${this.h(p.headshot_url)}" class="w-7 h-7 rounded-lg object-cover flex-shrink-0" alt="">`
                : `<span class="w-7 h-7 rounded-lg bg-pink-100 text-pink-600 flex items-center justify-center font-bold text-[10px] flex-shrink-0">${this.h(p.initials || (p.name || "?")[0])}</span>`
            return `
                <button type="button"
                        data-person-id="${p.id}"
                        data-action="click->shift-add#togglePerson"
                        class="relative flex items-center gap-2 px-2 py-1.5 rounded border border-gray-200 bg-white hover:border-pink-400 hover:bg-pink-50 transition-colors cursor-pointer text-left">
                    ${avatar}
                    <span class="min-w-0">
                        <span class="block text-xs font-medium text-gray-900 truncate">${this.h(p.name || "(no name)")}</span>
                        ${badge}
                    </span>
                </button>`
        }).join("")
    }

    badgeFor(personId) {
        if (this.isPerforming(personId)) {
            return `<span class="block text-[10px] text-purple-600 font-medium">In a show</span>`
        }
        if (this.isUnavailable(personId)) {
            return `<span class="block text-[10px] text-red-600 font-medium">Unavailable</span>`
        }
        return ""
    }

    togglePerson(event) {
        if (event) event.preventDefault()
        const btn = event.currentTarget
        const id = btn.dataset.personId
        const selecting = this.hasPersonIdInputTarget && this.personIdInputTarget.value !== id

        this.clearPerson()
        if (selecting) {
            if (this.hasPersonIdInputTarget) this.personIdInputTarget.value = id
            btn.classList.add("ring-2", "ring-pink-500", "border-pink-400", "bg-pink-50")
        }
    }

    clearPerson() {
        if (this.hasPersonIdInputTarget) this.personIdInputTarget.value = ""
        if (this.hasPeopleTarget) {
            this.peopleTarget.querySelectorAll("button").forEach(b =>
                b.classList.remove("ring-2", "ring-pink-500", "border-pink-400", "bg-pink-50"))
        }
    }

    // Same semantics as shift-assign: cast on this schedule day, or an
    // unavailability entry covering the shift's day part.
    isPerforming(personId) {
        if (!this.dayIso) return false
        const byDay = this.castByDay[this.dayIso] || {}
        return (byDay[String(personId)] || []).length > 0
    }

    isUnavailable(personId) {
        if (!this.dayIso) return false
        const data = this.unavailability[personId]
        if (!data) return false

        const start = this.hasStartTimeInputTarget ? this.startTimeInputTarget.value : ""
        const dayParts = dayPartsFor(start.slice(0, 5) || "17:00", this.dayParts)
        const entries = data.entries || []
        const covers = entries.some(e => entryCovers(e, this.dayIso, dayParts))
        return data.mode === "available" ? !covers : covers
    }

    // ----- plumbing -----

    setSubmitEnabled(enabled) {
        if (!this.hasSubmitWrapTarget) return
        this.submitWrapTarget.classList.toggle("opacity-40", !enabled)
        this.submitWrapTarget.classList.toggle("pointer-events-none", !enabled)
    }

    parse(json, fallback) {
        try { return JSON.parse(json || "") } catch (_) { return fallback }
    }

    nextDay(iso) {
        const d = new Date(`${iso}T12:00:00`)
        d.setDate(d.getDate() + 1)
        return d.toISOString().slice(0, 10)
    }

    fmt(time) {
        const [hh, mm] = time.split(":").map(n => parseInt(n, 10))
        const ampm = hh >= 12 ? "PM" : "AM"
        const h = hh % 12 || 12
        return `${h}:${String(mm).padStart(2, "0")} ${ampm}`
    }

    h(s) {
        if (s == null) return ""
        const d = document.createElement("div")
        d.textContent = String(s)
        return d.innerHTML
    }

    close(event) { if (event) event.preventDefault(); this.hide() }
    backdropClose(event) { if (event.target === this.modalTarget) this.hide() }
    stopPropagation(event) { event.stopPropagation() }
    show() { if (this.hasModalTarget) this.modalTarget.classList.remove("hidden") }
    hide() { if (this.hasModalTarget) this.modalTarget.classList.add("hidden") }
}
