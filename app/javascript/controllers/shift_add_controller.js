import { Controller } from "@hotwired/stimulus"

// Opens a modal for adding a shift on a given day. Pick a role and the shift's
// window is filled in from the day's shows. For "per-show" (show-specific)
// roles, a Show picker appears so the shift is tied to one chosen show and runs
// for that show's hours; house roles span the whole evening.
export default class extends Controller {
    static targets = ["modal", "form", "subtitle", "roleSelect", "startInput", "endInput", "timeHint",
                      "sourceTypeInput", "sourceIdInput", "showRow", "showSelect"]
    static values = { createUrl: String }

    open(event) {
        if (event) event.preventDefault()
        const btn = event.currentTarget
        const dayLabel = btn.dataset.dayLabel || ""

        this.roleDefaults = this.parse(btn.dataset.roleDefaults, {}) // { roleId: {starts_at, ends_at} }
        this.showDefaults = this.parse(btn.dataset.showDefaults, {}) // { roleId: { showId: {starts_at, ends_at} } }
        this.dayShows = this.parse(btn.dataset.dayShows, [])         // [{ id, label }]
        this.defaultSourceShowId = btn.dataset.sourceShowId || ""

        if (this.hasSubtitleTarget) this.subtitleTarget.textContent = dayLabel
        if (this.hasFormTarget && this.hasCreateUrlValue) this.formTarget.action = this.createUrlValue

        this.roleChanged()
        this.show()
    }

    // Role picked: show the per-show picker for show-specific roles, else fall
    // back to the whole-evening window anchored to the day's first show.
    roleChanged() {
        if (!this.hasRoleSelectTarget) return
        const roleId = this.roleSelectTarget.value
        const perShow = this.showDefaults[roleId]

        if (perShow && this.dayShows.length) {
            this.populateShowOptions()
            if (this.hasShowRowTarget) this.showRowTarget.classList.remove("hidden")
            this.showChanged()
        } else {
            if (this.hasShowRowTarget) this.showRowTarget.classList.add("hidden")
            const d = this.roleDefaults[roleId]
            if (d) this.applyTimes(d.starts_at, d.ends_at)
            this.setSource(this.defaultSourceShowId)
        }
    }

    // Show picked (per-show roles): anchor the shift to that show and use its hours.
    showChanged() {
        const perShow = this.showDefaults[this.roleSelectTarget.value]
        if (!perShow) return
        const showId = this.hasShowSelectTarget ? this.showSelectTarget.value : ""
        const d = perShow[showId]
        if (d) this.applyTimes(d.starts_at, d.ends_at)
        this.setSource(showId)
    }

    populateShowOptions() {
        if (!this.hasShowSelectTarget) return
        const current = this.showSelectTarget.value
        this.showSelectTarget.innerHTML = ""
        this.dayShows.forEach(s => {
            const opt = document.createElement("option")
            opt.value = s.id
            opt.textContent = s.label
            this.showSelectTarget.appendChild(opt)
        })
        if (current && this.dayShows.some(s => s.id === current)) this.showSelectTarget.value = current
    }

    applyTimes(startsAt, endsAt) {
        if (this.hasStartInputTarget) this.startInputTarget.value = startsAt
        if (this.hasEndInputTarget)   this.endInputTarget.value   = endsAt
        if (this.hasTimeHintTarget && startsAt && endsAt) {
            this.timeHintTarget.textContent = `Will run ${this.fmt(startsAt)} – ${this.fmt(endsAt)}.`
        }
    }

    setSource(showId) {
        if (this.hasSourceTypeInputTarget) this.sourceTypeInputTarget.value = showId ? "Show" : ""
        if (this.hasSourceIdInputTarget)   this.sourceIdInputTarget.value   = showId || ""
    }

    parse(json, fallback) {
        try { return JSON.parse(json || "") } catch (_) { return fallback }
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
