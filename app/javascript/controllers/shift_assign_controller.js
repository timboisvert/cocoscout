import { Controller } from "@hotwired/stimulus"

// Opens a modal for assigning staff to a specific shift. The available pool
// per house role is embedded on the page as JSON; this controller filters it
// against the shift's house_role_id and the already-assigned person ids.
//
// Before assigning, it checks whether the chosen person is already on another
// shift that overlaps in time and, if so, surfaces a conflict modal that
// illustrates the clash and asks how to proceed.
export default class extends Controller {
    static targets = [
        "modal", "title", "subtitle", "results", "form", "personIdInput",
        "collisionModal", "collisionBody", "filterAll", "filterAvailable"
    ]
    static values = {
        staffByRole: Object,         // { "<roleId>": [{ id, name, initials, headshot_url }, ...] }
        assignUrlTemplate: String,   // e.g. "/manage/staffing/shifts/:id/assign"
        shiftTimes: Object,          // { "<shiftId>": { starts_at, ends_at, role, day, cast_date, time_range } }
        personBusy: Object,          // { "<personId>": ["<shiftId>", ...] }
        staffUnavailability: Object, // { "<personId>": [{ date: "YYYY-MM-DD", scope }, ...] }
        castByDay: Object            // { "YYYY-MM-DD": { "<personId>": ["Show label", ...] } }
    }

    open(event) {
        if (event) event.preventDefault()
        const btn = event.currentTarget
        const shiftId = btn.dataset.shiftId
        const roleId = btn.dataset.roleId
        const roleName = btn.dataset.roleName || "this role"
        const timeRange = btn.dataset.timeRange || ""
        const assignedIds = JSON.parse(btn.dataset.assignedIds || "[]").map(String)

        this.currentShiftId = String(shiftId)
        this.currentRoleName = roleName
        this.currentTimeRange = timeRange

        // Derive the shift's date + day part (day/evening) from the times payload,
        // so we can flag people who marked themselves unavailable then.
        const times = (this.hasShiftTimesValue ? this.shiftTimesValue : {})[this.currentShiftId]
        if (times && times.starts_at) {
            this.currentShiftDate = times.starts_at.slice(0, 10)
            // Cast lives on the schedule day (which can differ from the literal
            // start date when a shift crosses midnight); fall back to start date.
            this.currentCastDate = times.cast_date || this.currentShiftDate
            const hour = parseInt(times.starts_at.slice(11, 13), 10)
            this.currentDayPart = hour >= 17 ? "evening" : "day"
        } else {
            this.currentShiftDate = null
            this.currentCastDate = null
            this.currentDayPart = null
        }

        if (this.hasTitleTarget) this.titleTarget.textContent = `Assign ${roleName}`
        if (this.hasSubtitleTarget) this.subtitleTarget.textContent = timeRange
        if (this.hasFormTarget && this.hasAssignUrlTemplateValue) {
            this.formTarget.action = this.assignUrlTemplateValue.replace(":id", shiftId)
        }

        this.currentPool = (this.staffByRoleValue && this.staffByRoleValue[roleId]) || []
        this.currentAssignedIds = assignedIds
        this.onlyAvailable = false
        this.updateFilterButtons()
        this.renderPeople(this.currentPool, assignedIds)
        this.show()
    }

    showAll(event) {
        if (event) event.preventDefault()
        this.onlyAvailable = false
        this.updateFilterButtons()
        if (this.currentPool) this.renderPeople(this.currentPool, this.currentAssignedIds || [])
    }

    showAvailableOnly(event) {
        if (event) event.preventDefault()
        this.onlyAvailable = true
        this.updateFilterButtons()
        if (this.currentPool) this.renderPeople(this.currentPool, this.currentAssignedIds || [])
    }

    updateFilterButtons() {
        const active = "bg-pink-500 text-white"
        const inactive = "bg-gray-100 text-gray-700 hover:bg-gray-200"
        if (this.hasFilterAllTarget) this.filterAllTarget.className = `px-3 py-1.5 rounded text-xs font-medium transition ${this.onlyAvailable ? inactive : active}`
        if (this.hasFilterAvailableTarget) this.filterAvailableTarget.className = `px-3 py-1.5 rounded text-xs font-medium transition ${this.onlyAvailable ? active : inactive}`
    }

    // Shows the person is cast in on this shift's day (they're a performer that
    // night). Returns an array of show labels; empty if none.
    castConflictsFor(personId) {
        if (!this.currentCastDate) return []
        const byDay = (this.hasCastByDayValue ? this.castByDayValue : {})[this.currentCastDate] || {}
        return byDay[String(personId)] || []
    }

    isPerforming(personId) {
        return this.castConflictsFor(personId).length > 0
    }

    // Is this person unavailable for the shift currently being assigned?
    isUnavailable(personId) {
        if (!this.currentShiftDate) return false
        const entries = (this.hasStaffUnavailabilityValue ? this.staffUnavailabilityValue : {})[personId] || []
        return entries.some(e => {
            if (e.date !== this.currentShiftDate) return false
            return e.scope === "all_day" ||
                   (e.scope === "day_shifts" && this.currentDayPart === "day") ||
                   (e.scope === "evening_shifts" && this.currentDayPart === "evening")
        })
    }

    close(event) {
        if (event) event.preventDefault()
        this.hide()
    }

    backdropClose(event) {
        if (event.target === this.modalTarget) this.hide()
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    pick(event) {
        if (event) event.preventDefault()
        const btn = event.currentTarget
        const id = btn.dataset.personId
        const name = btn.dataset.personName || "This person"
        if (!id) return

        const conflicts = this.findConflicts(id)
        const castConflicts = this.castConflictsFor(id)
        if (conflicts.length > 0 || castConflicts.length > 0) {
            this.showCollision(id, name, conflicts, castConflicts)
            return
        }
        this.submitAssign(id)
    }

    // ----- collision flow -----

    // Returns the time spans of other shifts the person is already on that
    // overlap the shift currently being assigned.
    findConflicts(personId) {
        const times = this.hasShiftTimesValue ? this.shiftTimesValue : {}
        const busy = (this.hasPersonBusyValue ? this.personBusyValue : {})[personId] || []
        const current = times[this.currentShiftId]
        if (!current) return []

        const cs = new Date(current.starts_at).getTime()
        const ce = new Date(current.ends_at).getTime()

        return busy
            .filter(sid => String(sid) !== this.currentShiftId)
            .map(sid => times[sid])
            .filter(t => t && new Date(t.starts_at).getTime() < ce && new Date(t.ends_at).getTime() > cs)
    }

    showCollision(personId, personName, conflicts, castConflicts = []) {
        this.pendingPersonId = personId
        if (this.hasCollisionBodyTarget) {
            let html = ""

            // Section 1: they're performing in a show that day.
            if (castConflicts.length > 0) {
                const castRows = castConflicts.map(label => `
                    <div class="flex items-center gap-2 rounded border border-purple-200 bg-purple-50 px-3 py-2">
                        <svg class="w-4 h-4 text-purple-500 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20"><path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.286 3.957a1 1 0 00.95.69h4.162c.969 0 1.371 1.24.588 1.81l-3.367 2.446a1 1 0 00-.364 1.118l1.287 3.957c.3.922-.755 1.688-1.54 1.118l-3.366-2.446a1 1 0 00-1.175 0l-3.367 2.446c-.784.57-1.838-.196-1.539-1.118l1.286-3.957a1 1 0 00-.363-1.118L2.07 9.384c-.783-.57-.38-1.81.588-1.81h4.162a1 1 0 00.95-.69l1.287-3.957z"/></svg>
                        <span class="text-purple-900 text-sm">Performing in <span class="font-medium">${this.h(label)}</span></span>
                    </div>`).join("")
                html += `
                    <p class="text-sm text-gray-700">
                        <span class="font-semibold">${this.h(personName)}</span> is also in a show on this day:
                    </p>
                    <div class="mt-3 space-y-2">${castRows}</div>`
            }

            // Section 2: overlapping shift (existing double-book check).
            if (conflicts.length > 0) {
                const rows = conflicts.map(c => `
                    <div class="flex items-center justify-between gap-3 rounded border border-amber-200 bg-amber-50 px-3 py-2">
                        <span class="font-medium text-amber-900">${this.h(c.role)}</span>
                        <span class="text-amber-800 tabular-nums text-xs">${this.h(c.day)} · ${this.h(c.time_range)}</span>
                    </div>`).join("")
                html += `
                    <p class="text-sm text-gray-700 ${castConflicts.length > 0 ? "mt-4" : ""}">
                        <span class="font-semibold">${this.h(personName)}</span> is already assigned to a
                        shift that overlaps this one:
                    </p>
                    <div class="mt-3 space-y-2">${rows}</div>
                    <div class="mt-3 rounded border border-pink-200 bg-pink-50 px-3 py-2 flex items-center justify-between gap-3">
                        <span class="font-medium text-pink-900">${this.h(this.currentRoleName)} (new)</span>
                        <span class="text-pink-800 tabular-nums text-xs">${this.h(this.currentTimeRange)}</span>
                    </div>`
            }

            const note = conflicts.length > 0
                ? `Assigning anyway double-books ${this.h(personName)} for overlapping times.`
                : `Assigning anyway staffs ${this.h(personName)} on a night they're performing.`
            html += `<p class="mt-3 text-xs text-gray-500">${note}</p>`

            this.collisionBodyTarget.innerHTML = html
        }
        if (this.hasCollisionModalTarget) this.collisionModalTarget.classList.remove("hidden")
    }

    confirmCollision(event) {
        if (event) event.preventDefault()
        if (this.hasCollisionModalTarget) this.collisionModalTarget.classList.add("hidden")
        if (this.pendingPersonId) this.submitAssign(this.pendingPersonId)
    }

    cancelCollision(event) {
        if (event) event.preventDefault()
        this.pendingPersonId = null
        if (this.hasCollisionModalTarget) this.collisionModalTarget.classList.add("hidden")
    }

    collisionBackdropClose(event) {
        if (event.target === this.collisionModalTarget) this.cancelCollision()
    }

    submitAssign(personId) {
        if (!this.hasPersonIdInputTarget || !this.hasFormTarget) return
        this.personIdInputTarget.value = personId
        this.formTarget.requestSubmit()
    }

    // ----- private -----

    show() {
        if (this.hasModalTarget) this.modalTarget.classList.remove("hidden")
    }
    hide() {
        if (this.hasModalTarget) this.modalTarget.classList.add("hidden")
    }

    renderPeople(people, assignedIds) {
        if (!this.hasResultsTarget) return
        if (people.length === 0) {
            this.resultsTarget.innerHTML = `
                <p class="text-sm text-gray-500 text-center py-8">
                    No one is qualified for this role yet.
                    <br/>
                    <a href="/manage/staffing/staff" class="text-pink-600 underline">Add staff and mark their roles</a>.
                </p>`
            return
        }
        const visible = this.onlyAvailable ? people.filter(p => !this.isUnavailable(p.id)) : people

        if (visible.length === 0) {
            this.resultsTarget.innerHTML = `<p class="text-sm text-gray-500 text-center py-8">No available staff for this shift.</p>`
            return
        }

        const cards = visible.map(p => {
            const isAssigned = assignedIds.includes(String(p.id))
            const unavailable = this.isUnavailable(p.id)
            const performing = this.isPerforming(p.id)
            const avatar = p.headshot_url
                ? `<img src="${this.h(p.headshot_url)}" class="w-16 h-16 rounded-lg object-cover" alt="">`
                : `<div class="w-16 h-16 rounded-lg bg-pink-100 text-pink-600 flex items-center justify-center font-bold text-lg">${this.h(p.initials || (p.name||"?")[0])}</div>`
            // Badge precedence: Assigned > In a show > Unavailable.
            let badge = ""
            if (isAssigned) {
                badge = `<span class="absolute top-1.5 right-1.5 inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded bg-green-100 text-green-700 text-[10px] font-medium">Assigned</span>`
            } else if (performing) {
                badge = `<span class="absolute top-1.5 right-1.5 inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded bg-purple-100 text-purple-700 text-[10px] font-medium">In a show</span>`
            } else if (unavailable) {
                badge = `<span class="absolute top-1.5 right-1.5 inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded bg-red-100 text-red-700 text-[10px] font-medium">Unavailable</span>`
            }
            const disabledAttr = isAssigned ? "disabled" : ""
            let buttonClass
            if (isAssigned) {
                buttonClass = "relative bg-gray-50 border border-gray-200 rounded-lg p-4 flex flex-col items-center gap-2.5 text-center opacity-50 cursor-not-allowed"
            } else if (performing) {
                buttonClass = "relative bg-white border border-purple-200 rounded-lg p-4 flex flex-col items-center gap-2.5 text-center hover:border-purple-400 hover:bg-purple-50 transition-colors cursor-pointer"
            } else if (unavailable) {
                buttonClass = "relative bg-white border border-red-200 rounded-lg p-4 flex flex-col items-center gap-2.5 text-center opacity-70 hover:border-red-400 hover:bg-red-50 transition-colors cursor-pointer"
            } else {
                buttonClass = "relative bg-white border border-gray-200 rounded-lg p-4 flex flex-col items-center gap-2.5 text-center hover:border-pink-400 hover:bg-pink-50 transition-colors cursor-pointer"
            }
            return `
                <button type="button"
                        data-person-id="${p.id}"
                        data-person-name="${this.h(p.name || "")}"
                        data-action="click->shift-assign#pick"
                        class="${buttonClass}"
                        ${disabledAttr}>
                    ${badge}
                    ${avatar}
                    <div class="text-sm font-medium text-gray-900 w-full leading-tight break-words">${this.h(p.name || "(no name)")}</div>
                </button>`
        }).join("")
        this.resultsTarget.innerHTML = `<div class="grid grid-cols-2 sm:grid-cols-3 gap-3">${cards}</div>`
    }

    h(s) {
        if (s == null) return ""
        const d = document.createElement("div")
        d.textContent = String(s)
        return d.innerHTML
    }
}
