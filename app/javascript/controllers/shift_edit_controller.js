import { Controller } from "@hotwired/stimulus"

// Opens a modal for editing a single shift's start/end times.
// The user only sees time inputs (HH:MM). The shift's original date is kept
// internally and stitched back onto the time before submit. End time is
// allowed to roll into the next day if it's earlier than the start.
//
// If the click came from a specific person's chip/block (Gantt views), a
// "Remove [name] from this shift" button appears at the bottom. The person
// context is read by walking up from event.target to the nearest element
// carrying data-person-id, so a click on the outer block (no chip hit) keeps
// the modal in time-edit-only mode.
export default class extends Controller {
    static targets = [
        "modal", "form", "title", "dayLabel",
        "startTimeInput", "endTimeInput", "startInput", "endInput",
        "additionalRoleCheckbox",
        "removeSection", "removeButton", "removePersonName"
    ]
    static values = {
        updateUrlTemplate: String,
        unassignUrlTemplate: String  // e.g. "/manage/staffing/shifts/SHIFT_ID/unassign/PERSON_ID"
    }

    open(event) {
        if (event) event.preventDefault()
        const btn = event.currentTarget
        const id = btn.dataset.shiftId
        const startAt = btn.dataset.shiftStartsAt  // "YYYY-MM-DDTHH:MM"
        const endAt = btn.dataset.shiftEndsAt
        const roleName = btn.dataset.shiftRoleName || "shift"

        // Was a specific person chip clicked? Walk up from the actual click target.
        const personEl = event.target && event.target.closest
            ? event.target.closest("[data-person-id]")
            : null
        this.currentShiftId = id
        this.currentPersonId = personEl && personEl.dataset.personId
        const personName = personEl && personEl.dataset.personName

        // Parse without timezone math — these strings are already local.
        const [startDate, startTime] = startAt.split("T")
        const [endDate, endTime] = endAt.split("T")
        this.startDate = startDate
        this.endDate = endDate

        if (this.hasTitleTarget) this.titleTarget.textContent = `Edit ${roleName} shift`
        if (this.hasDayLabelTarget) {
            this.dayLabelTarget.textContent = this.formatDayLabel(startDate)
        }
        if (this.hasStartTimeInputTarget) this.startTimeInputTarget.value = startTime
        if (this.hasEndTimeInputTarget) this.endTimeInputTarget.value = endTime

        // Preselect the "also covers" roles, if any (JSON array of role ids),
        // and disable the shift's own primary role so it can't double itself.
        if (this.hasAdditionalRoleCheckboxTarget) {
            let ids = []
            try { ids = JSON.parse(btn.dataset.shiftAdditionalRoleIds || "[]") } catch (e) { ids = [] }
            const idSet = new Set(ids.map(String))
            const primaryId = btn.dataset.shiftHouseRoleId ? String(btn.dataset.shiftHouseRoleId) : null
            this.additionalRoleCheckboxTargets.forEach(cb => {
                const isPrimary = primaryId && String(cb.value) === primaryId
                cb.disabled = !!isPrimary
                cb.checked = !isPrimary && idSet.has(String(cb.value))
                const label = cb.closest("label")
                if (label) label.classList.toggle("opacity-40", !!isPrimary)
            })
        }

        this.syncHiddenFields()

        if (this.hasFormTarget && this.hasUpdateUrlTemplateValue) {
            this.formTarget.action = this.updateUrlTemplateValue.replace(":id", id)
            this.formTarget.addEventListener("submit", this.syncHiddenFields.bind(this), { once: true })
        }

        // Toggle the per-person remove section.
        if (this.hasRemoveSectionTarget) {
            const showRemove = !!(this.currentPersonId && this.hasUnassignUrlTemplateValue)
            this.removeSectionTarget.classList.toggle("hidden", !showRemove)
            if (showRemove && this.hasRemovePersonNameTarget) {
                this.removePersonNameTarget.textContent = personName || "this person"
            }
        }

        this.show()
    }

    // Recompute the hidden full-datetime fields from the time inputs. If the
    // end time is at or before the start time, assume the shift crosses
    // midnight and roll the end date forward by one day.
    syncHiddenFields() {
        if (!this.hasStartTimeInputTarget || !this.hasEndTimeInputTarget) return
        const startTime = this.startTimeInputTarget.value
        const endTime = this.endTimeInputTarget.value
        if (!startTime || !endTime) return

        const startISO = `${this.startDate}T${startTime}`
        let endDate = this.startDate
        if (endTime <= startTime) {
            const d = new Date(`${this.startDate}T00:00:00`)
            d.setDate(d.getDate() + 1)
            endDate = d.toISOString().slice(0, 10)
        }
        const endISO = `${endDate}T${endTime}`

        if (this.hasStartInputTarget) this.startInputTarget.value = startISO
        if (this.hasEndInputTarget) this.endInputTarget.value = endISO
    }

    // Confirms, then submits a DELETE to /unassign via a one-off hidden form.
    removePerson(event) {
        if (event) event.preventDefault()
        if (!this.currentShiftId || !this.currentPersonId || !this.hasUnassignUrlTemplateValue) return
        const name = this.hasRemovePersonNameTarget ? this.removePersonNameTarget.textContent : "this person"
        if (!window.confirm(`Remove ${name} from this shift?`)) return

        const url = this.unassignUrlTemplateValue
            .replace("SHIFT_ID", this.currentShiftId)
            .replace("PERSON_ID", this.currentPersonId)

        const form = document.createElement("form")
        form.method = "POST"
        form.action = url
        form.style.display = "none"

        const methodInput = document.createElement("input")
        methodInput.type = "hidden"
        methodInput.name = "_method"
        methodInput.value = "delete"
        form.appendChild(methodInput)

        const csrfMeta = document.querySelector('meta[name="csrf-token"]')
        if (csrfMeta) {
            const csrfInput = document.createElement("input")
            csrfInput.type = "hidden"
            csrfInput.name = "authenticity_token"
            csrfInput.value = csrfMeta.content
            form.appendChild(csrfInput)
        }

        document.body.appendChild(form)
        form.submit()
    }

    formatDayLabel(dateString) {
        const d = new Date(`${dateString}T12:00:00`)
        return d.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" })
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

    show() { if (this.hasModalTarget) this.modalTarget.classList.remove("hidden") }
    hide() { if (this.hasModalTarget) this.modalTarget.classList.add("hidden") }
}
