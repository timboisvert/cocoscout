import { Controller } from "@hotwired/stimulus"

// Assigning staff to a shift through the shared People Picker (V1.1 plan
// §5; shared/_people_picker, "shift-picker"): the server lists everyone
// qualified for the shift's role with what they said about the hours, and
// each pick carries the clashes (another shift that overlaps, a show that
// night, hours they can't work) so the conflict modal can ask first.
export default class extends Controller {
    static targets = [
        "form", "personIdInput",
        "collisionModal", "collisionBody"
    ]
    static values = {
        assignUrlTemplate: String    // e.g. "/manage/staffing/shifts/:id/assign"
    }

    open(event) {
        if (event) event.preventDefault()
        const btn = event.currentTarget
        const shiftId = String(btn.dataset.shiftId)
        const roleName = btn.dataset.roleName || "this role"
        const timeRange = btn.dataset.timeRange || ""

        this.currentShiftId = shiftId
        this.currentRoleName = roleName
        this.currentTimeRange = timeRange
        if (this.hasFormTarget && this.hasAssignUrlTemplateValue) {
            this.formTarget.action = this.assignUrlTemplateValue.replace(":id", shiftId)
        }
        window.dispatchEvent(new CustomEvent("people-picker:open", {
            detail: { id: "shift-picker", title: `Assign ${roleName} · ${timeRange}`.trim(), context: { shift_id: shiftId }, params: { shift_id: shiftId } }
        }))
    }

    close(event) {
        if (event) event.preventDefault()
        this.hide()
    }

    // people-picker:pick: assign, or ask first when it collides.
    picked(event) {
        const pick = event.detail
        if (pick.picker !== "shift-picker" || pick.type !== "Person") return
        const id = String(pick.id)
        const name = pick.name || "This person"
        const staff = pick.staff || {}
        const conflicts = staff.conflicts || []
        const castConflicts = staff.cast || []
        const verdict = staff.verdict || { status: "free" }
        const unavailable = verdict.status === "blocked" || verdict.status === "partial"
        if (conflicts.length > 0 || castConflicts.length > 0 || unavailable) {
            this.showCollision(id, name, conflicts, castConflicts, unavailable ? verdict : null)
            return
        }
        this.submitAssign(id)
    }

    // ----- collision flow -----

    showCollision(personId, personName, conflicts, castConflicts = [], verdict = null) {
        this.pendingPersonId = personId
        if (this.hasCollisionBodyTarget) {
            let html = ""

            // Section 0: what they said about when they can work.
            if (verdict) {
                const tone = verdict.status === "blocked"
                    ? "border-red-200 bg-red-50 text-red-900"
                    : "border-amber-200 bg-amber-50 text-amber-900"
                html += `
                    <p class="text-sm text-gray-700">
                        <span class="font-semibold">${this.h(personName)}</span> said they can't work all of this shift:
                    </p>
                    <div class="mt-3 rounded border ${tone} px-3 py-2 text-sm">${this.h(verdict.detail || verdict.badge || "")}</div>`
            }

            // Section 1: they're performing in a show that day.
            if (castConflicts.length > 0) {
                const castRows = castConflicts.map(label => `
                    <div class="flex items-center gap-2 rounded border border-purple-200 bg-purple-50 px-3 py-2">
                        <svg class="w-4 h-4 text-purple-500 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20"><path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.286 3.957a1 1 0 00.95.69h4.162c.969 0 1.371 1.24.588 1.81l-3.367 2.446a1 1 0 00-.364 1.118l1.287 3.957c.3.922-.755 1.688-1.54 1.118l-3.366-2.446a1 1 0 00-1.175 0l-3.367 2.446c-.784.57-1.838-.196-1.539-1.118l1.286-3.957a1 1 0 00-.363-1.118L2.07 9.384c-.783-.57-.38-1.81.588-1.81h4.162a1 1 0 00.95-.69l1.287-3.957z"/></svg>
                        <span class="text-purple-900 text-sm">Performing in <span class="font-medium">${this.h(label)}</span></span>
                    </div>`).join("")
                html += `
                    <p class="text-sm text-gray-700 ${verdict ? "mt-4" : ""}">
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
                    <p class="text-sm text-gray-700 ${castConflicts.length > 0 || verdict ? "mt-4" : ""}">
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
                : castConflicts.length > 0
                    ? `Assigning anyway staffs ${this.h(personName)} on a night they're performing.`
                    : `Assigning anyway puts ${this.h(personName)} on a shift they said they can't fully work.`
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

    hide() {
        document.getElementById("shift-picker")?.classList.add("hidden")
    }

    h(s) {
        if (s == null) return ""
        const d = document.createElement("div")
        d.textContent = String(s)
        return d.innerHTML
    }
}
