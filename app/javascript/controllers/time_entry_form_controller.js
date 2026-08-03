import { Controller } from "@hotwired/stimulus"

// Drives the shared "log time" modal on My Shifts. A trigger button carries the
// mode (confirm / manual / edit), the target form URL + method, and any
// prefill (assignment id, start/end, notes, role); load() fills the form, and
// recalc() shows the live hours between the two datetime-local inputs.
//
// Role: self-logged (manual) work picks the role it was done as — that's what
// prices the hours. The role options are filtered to the entry's org; the row
// hides when that org has no roles for this person. Shift confirmations carry
// the shift's role, so the picker stays hidden for them.
export default class extends Controller {
    static targets = ["form", "methodInput", "assignmentInput", "orgRow", "orgSelect",
                      "roleRow", "roleSelect", "shiftNote",
                      "title", "started", "ended", "hours", "notes"]

    load(event) {
        const d = event.currentTarget.dataset
        const manual = d.mode === "manual"
        // Editing a self-logged entry also gets the role picker (its trigger
        // says so); shift-backed entries never do.
        const roleEditable = manual || d.roleEditable === "true"

        if (this.hasFormTarget && d.url) this.formTarget.action = d.url
        if (this.hasMethodInputTarget) this.methodInputTarget.value = d.method || "post"
        if (this.hasTitleTarget) this.titleTarget.textContent = d.title || "Log time"
        if (this.hasAssignmentInputTarget) this.assignmentInputTarget.value = d.assignmentId || ""
        if (this.hasOrgRowTarget) this.orgRowTarget.classList.toggle("hidden", !manual)
        // Shift verifications get the "these are your scheduled hours" explainer.
        if (this.hasShiftNoteTarget) this.shiftNoteTarget.classList.toggle("hidden", d.mode !== "confirm")
        // Disabled inputs don't submit — keep org out of confirm/edit posts.
        if (this.hasOrgSelectTarget) this.orgSelectTarget.disabled = !manual

        this.roleEditable = roleEditable
        // Filter roles by the entry's org: the picker (manual) or the trigger (edit).
        this.currentOrgId = manual ? this.orgValue() : (d.orgId || "")
        this.applyRoleFilter(d.houseRoleId || "")

        if (this.hasStartedTarget) this.startedTarget.value = d.started || ""
        if (this.hasEndedTarget) this.endedTarget.value = d.ended || ""
        if (this.hasNotesTarget) this.notesTarget.value = d.notes || ""
        this.recalc()
    }

    orgChanged() {
        this.currentOrgId = this.orgValue()
        this.applyRoleFilter("")
    }

    // Show only the selected org's roles; hide the whole row when there are
    // none (or the role isn't editable for this entry).
    applyRoleFilter(selectedRoleId) {
        if (!this.hasRoleSelectTarget) return

        let visible = 0
        Array.from(this.roleSelectTarget.options).forEach(opt => {
            if (!opt.dataset.orgId) return // the "no specific role" option
            const match = opt.dataset.orgId === String(this.currentOrgId)
            opt.hidden = !match
            opt.disabled = !match
            if (match) visible++
        })

        const usable = this.roleEditable && visible > 0
        if (this.hasRoleRowTarget) this.roleRowTarget.classList.toggle("hidden", !usable)
        this.roleSelectTarget.disabled = !usable

        const wanted = selectedRoleId ? String(selectedRoleId) : ""
        const wantedOpt = wanted && Array.from(this.roleSelectTarget.options).find(o => o.value === wanted && !o.disabled)
        this.roleSelectTarget.value = wantedOpt ? wanted : ""
    }

    orgValue() {
        return this.hasOrgSelectTarget ? this.orgSelectTarget.value : ""
    }

    recalc() {
        const s = this.hasStartedTarget ? Date.parse(this.startedTarget.value) : NaN
        const e = this.hasEndedTarget ? Date.parse(this.endedTarget.value) : NaN
        let hours = 0
        if (!isNaN(s) && !isNaN(e) && e > s) hours = (e - s) / 3600000
        if (this.hasHoursTarget) this.hoursTarget.textContent = String(Math.round(hours * 100) / 100)
    }
}
