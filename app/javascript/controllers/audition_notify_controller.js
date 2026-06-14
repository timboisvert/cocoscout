import { Controller } from "@hotwired/stimulus"

// "Review & Notify" modal on the audition scheduling page. On open it fetches a
// fresh preview of who's getting an audition vs not (scheduling changes after
// page load), fills the two lists, and lets the manager edit the two messages
// before submitting the finalize-and-notify form.
export default class extends Controller {
    static targets = [
        "modal", "summary", "invitedList", "notInvitedList",
        "invitedCount", "notInvitedCount", "alreadyNotified"
    ]
    static values = { previewUrl: String }

    open(event) {
        if (event) event.preventDefault()
        this.show()
        this.loadPreview()
    }

    loadPreview() {
        fetch(this.previewUrlValue, { headers: { "Accept": "application/json" } })
            .then(r => r.ok ? r.json() : null)
            .then(data => { if (data) this.render(data) })
            .catch(e => console.error("[audition-notify] preview failed", e))
    }

    render(data) {
        if (this.hasSummaryTarget) {
            this.summaryTarget.textContent =
                `${data.invited_count} getting an audition · ${data.not_invited_count} not`
        }
        if (this.hasInvitedCountTarget) this.invitedCountTarget.textContent = `(${data.invited_count})`
        if (this.hasNotInvitedCountTarget) this.notInvitedCountTarget.textContent = `(${data.not_invited_count})`
        if (this.hasInvitedListTarget) this.invitedListTarget.innerHTML = this.listHtml(data.invited, true)
        if (this.hasNotInvitedListTarget) this.notInvitedListTarget.innerHTML = this.listHtml(data.not_invited, false)

        if (this.hasAlreadyNotifiedTarget) {
            if (data.already_notified_count > 0) {
                this.alreadyNotifiedTarget.hidden = false
                this.alreadyNotifiedTarget.textContent =
                    `${data.already_notified_count} of these auditionees were already notified earlier. Sending again will re-notify everyone whose status changed.`
            } else {
                this.alreadyNotifiedTarget.hidden = true
            }
        }
    }

    listHtml(people, showSessions) {
        if (!people || people.length === 0) {
            return `<div class="px-3 py-6 text-center text-sm text-gray-400">No one</div>`
        }
        return people.map(p => {
            const avatar = p.headshot
                ? `<img src="${this.h(p.headshot)}" class="w-8 h-8 rounded-lg object-cover flex-shrink-0" alt="">`
                : `<div class="w-8 h-8 rounded-lg bg-gray-100 text-gray-600 flex items-center justify-center text-[10px] font-bold flex-shrink-0">${this.h(p.initials || "?")}</div>`
            const sessions = (showSessions && p.sessions && p.sessions.length)
                ? `<div class="text-[11px] text-gray-500 truncate">${this.h(p.sessions.join(" · "))}</div>` : ""
            const notified = p.notified
                ? `<span class="text-[10px] px-1.5 py-0.5 rounded-full bg-gray-100 text-gray-500 flex-shrink-0">Notified</span>` : ""
            return `<div class="flex items-center gap-2.5 px-3 py-2">
                ${avatar}
                <div class="flex-1 min-w-0">
                    <div class="text-sm text-gray-900 truncate">${this.h(p.name)}</div>
                    ${sessions}
                </div>
                ${notified}
            </div>`
        }).join("")
    }

    close(event) { if (event) event.preventDefault(); this.hide() }
    backdropClose(event) { if (event.target === this.modalTarget) this.hide() }
    stopPropagation(event) { event.stopPropagation() }
    show() { if (this.hasModalTarget) this.modalTarget.classList.remove("hidden") }
    hide() { if (this.hasModalTarget) this.modalTarget.classList.add("hidden") }

    h(s) {
        if (s == null) return ""
        const d = document.createElement("div")
        d.textContent = String(s)
        return d.innerHTML
    }
}
