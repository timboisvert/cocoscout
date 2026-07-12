import { Controller } from "@hotwired/stimulus"

// Drives the shared "log time" modal on My Shifts. A trigger button carries the
// mode (confirm / manual / edit), the target form URL + method, and any
// prefill (assignment id, start/end, notes); load() fills the form, and recalc()
// shows the live hours between the two datetime-local inputs.
export default class extends Controller {
    static targets = ["form", "methodInput", "assignmentInput", "orgRow", "orgSelect",
                      "title", "started", "ended", "hours", "notes"]

    load(event) {
        const d = event.currentTarget.dataset
        const manual = d.mode === "manual"

        if (this.hasFormTarget && d.url) this.formTarget.action = d.url
        if (this.hasMethodInputTarget) this.methodInputTarget.value = d.method || "post"
        if (this.hasTitleTarget) this.titleTarget.textContent = d.title || "Log time"
        if (this.hasAssignmentInputTarget) this.assignmentInputTarget.value = d.assignmentId || ""
        if (this.hasOrgRowTarget) this.orgRowTarget.classList.toggle("hidden", !manual)
        // Disabled inputs don't submit — keep org out of confirm/edit posts.
        if (this.hasOrgSelectTarget) this.orgSelectTarget.disabled = !manual
        if (this.hasStartedTarget) this.startedTarget.value = d.started || ""
        if (this.hasEndedTarget) this.endedTarget.value = d.ended || ""
        if (this.hasNotesTarget) this.notesTarget.value = d.notes || ""
        this.recalc()
    }

    recalc() {
        const s = this.hasStartedTarget ? Date.parse(this.startedTarget.value) : NaN
        const e = this.hasEndedTarget ? Date.parse(this.endedTarget.value) : NaN
        let hours = 0
        if (!isNaN(s) && !isNaN(e) && e > s) hours = (e - s) / 3600000
        if (this.hasHoursTarget) this.hoursTarget.textContent = String(Math.round(hours * 100) / 100)
    }
}
