import { Controller } from "@hotwired/stimulus"

// Opens a modal for adding a shift on a given day. The user just picks a
// role — start/end times come from a per-day per-role defaults map that
// matches what the generator would produce, so re-adding a removed role is
// the same as if Generate had created it.
export default class extends Controller {
    static targets = ["modal", "form", "subtitle", "roleSelect", "startInput", "endInput", "timeHint", "sourceTypeInput", "sourceIdInput"]
    static values = { createUrl: String }

    open(event) {
        if (event) event.preventDefault()
        const btn = event.currentTarget
        const dayLabel = btn.dataset.dayLabel || ""

        try {
            this.roleDefaults = JSON.parse(btn.dataset.roleDefaults || "{}")
        } catch (_) {
            this.roleDefaults = {}
        }

        if (this.hasSubtitleTarget) this.subtitleTarget.textContent = dayLabel
        if (this.hasFormTarget && this.hasCreateUrlValue) this.formTarget.action = this.createUrlValue

        // Anchor the new shift to the day's show (if any) so it groups on the
        // show's day even when its hours cross midnight.
        const sourceShowId = btn.dataset.sourceShowId
        if (this.hasSourceTypeInputTarget) this.sourceTypeInputTarget.value = sourceShowId ? "Show" : ""
        if (this.hasSourceIdInputTarget)   this.sourceIdInputTarget.value   = sourceShowId || ""

        this.roleChanged()
        this.show()
    }

    // Populate hidden start/end + the visible time hint from the selected role.
    roleChanged() {
        if (!this.hasRoleSelectTarget) return
        const roleId = this.roleSelectTarget.value
        const defaults = this.roleDefaults[roleId]
        if (!defaults) return

        if (this.hasStartInputTarget) this.startInputTarget.value = defaults.starts_at
        if (this.hasEndInputTarget)   this.endInputTarget.value   = defaults.ends_at
        if (this.hasTimeHintTarget) {
            this.timeHintTarget.textContent = `Will run ${this.fmt(defaults.starts_at)} – ${this.fmt(defaults.ends_at)} (using the role's default offsets).`
        }
    }

    fmt(localIso) {
        // localIso is "YYYY-MM-DDTHH:MM" in local time; format as h:MM AM/PM.
        const [, time] = localIso.split("T")
        const [hh, mm] = time.split(":").map(n => parseInt(n, 10))
        const ampm = hh >= 12 ? "PM" : "AM"
        const h = hh % 12 || 12
        return `${h}:${String(mm).padStart(2, "0")} ${ampm}`
    }

    close(event) { if (event) event.preventDefault(); this.hide() }
    backdropClose(event) { if (event.target === this.modalTarget) this.hide() }
    stopPropagation(event) { event.stopPropagation() }
    show() { if (this.hasModalTarget) this.modalTarget.classList.remove("hidden") }
    hide() { if (this.hasModalTarget) this.modalTarget.classList.add("hidden") }
}
