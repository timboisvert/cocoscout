import { Controller } from "@hotwired/stimulus"

// Click-to-add scheduling for audition sessions. Each session has an "Add"
// slot; clicking it opens a modal listing auditionees — those marked available
// for that session first (ordered by votes), then everyone else. Picking one
// POSTs to add_to_session and swaps the session's slots with fresh server HTML.
// Removing happens by hovering an assigned card (handled here too).
export default class extends Controller {
    static targets = ["modal", "subtitle", "results", "sessionSlots", "filterAvailable", "filterAll", "search", "hideScheduled"]
    static values = {
        payload: Object,   // { requests: [...], availability: {sid:{rid:status}}, inSession: {sid:[rid]}, scheduledRequestIds: [rid] }
        addUrl: String,
        removeUrl: String
    }

    connect() {
        this.availableOnly = true
        this.searchTerm = ""
        // Normalize inSession to Sets keyed by string session id.
        this.inSession = {}
        const src = this.payloadValue.inSession || {}
        Object.keys(src).forEach(sid => { this.inSession[sid] = new Set((src[sid] || []).map(String)) })
        this.scheduled = new Set((this.payloadValue.scheduledRequestIds || []).map(String))
    }

    // Delegated click on a session's slots: open the add modal or remove a card.
    // Delegation keeps this working after the slots' innerHTML is swapped.
    slotsClick(event) {
        const removeBtn = event.target.closest("[data-audition-id]")
        if (removeBtn) { this.removeAudition(removeBtn); return }
        const addBtn = event.target.closest("[data-add-slot]")
        if (addBtn) this.open(addBtn)
    }

    // Delegated click inside the modal results list.
    resultsClick(event) {
        const btn = event.target.closest("button[data-request-id]")
        if (!btn || btn.disabled) return
        this.addRequest(btn.dataset.requestId)
    }

    // ----- modal -----
    open(btn) {
        this.currentSessionId = String(btn.dataset.sessionId)
        this.availableOnly = true
        this.searchTerm = ""
        if (this.hasSearchTarget) this.searchTarget.value = ""
        if (this.hasHideScheduledTarget) this.hideScheduled = this.hideScheduledTarget.checked
        this.updateFilterButtons()
        if (this.hasSubtitleTarget) {
            const label = btn.dataset.sessionLabel
            this.subtitleTarget.textContent = label ? `Adding to ${label}` : "Available auditionees show first, sorted by votes."
        }
        this.renderList()
        this.show()
        if (this.hasSearchTarget) setTimeout(() => this.searchTarget.focus(), 50)
    }

    showAvailableOnly(event) { if (event) event.preventDefault(); this.availableOnly = true; this.updateFilterButtons(); this.renderList() }
    showAll(event) { if (event) event.preventDefault(); this.availableOnly = false; this.updateFilterButtons(); this.renderList() }
    toggleHideScheduled(event) { this.hideScheduled = event.currentTarget.checked; this.renderList() }
    search(event) { this.searchTerm = (event.currentTarget.value || "").trim().toLowerCase(); this.renderList() }

    updateFilterButtons() {
        const active = "bg-pink-500 text-white"
        const idle = "bg-gray-100 text-gray-700 hover:bg-gray-200"
        if (this.hasFilterAvailableTarget) this.filterAvailableTarget.className = `px-3 py-1.5 rounded text-xs font-medium transition cursor-pointer ${this.availableOnly ? active : idle}`
        if (this.hasFilterAllTarget) this.filterAllTarget.className = `px-3 py-1.5 rounded text-xs font-medium transition cursor-pointer ${this.availableOnly ? idle : active}`
    }

    statusFor(requestId) {
        const sessionMap = (this.payloadValue.availability || {})[this.currentSessionId] || {}
        return sessionMap[String(requestId)] || "unset"
    }

    // Already on the schedule for this cycle (any session), incl. just-added.
    isScheduled(requestId) {
        const id = String(requestId)
        if (this.scheduled.has(id)) return true
        const inThis = this.inSession[this.currentSessionId]
        return inThis ? inThis.has(id) : false
    }

    renderList() {
        if (!this.hasResultsTarget) return
        const requests = this.payloadValue.requests || []
        const inThis = this.inSession[this.currentSessionId] || new Set()

        const passesFilters = (r) => {
            if (this.searchTerm && !String(r.name || "").toLowerCase().includes(this.searchTerm)) return false
            if (this.hideScheduled && this.isScheduled(r.id)) return false
            return true
        }

        // Requests arrive already vote-ordered from the server.
        const available = []
        const others = []
        requests.forEach(r => {
            if (!passesFilters(r)) return
            if (this.statusFor(r.id) === "available") available.push(r)
            else others.push(r)
        })

        let html = this.sectionHtml("Available for this session", available, inThis)
        if (!this.availableOnly) {
            html += this.sectionHtml("Not marked available", others, inThis)
        }

        if (html === "") {
            html = `<div class="text-center py-10 text-sm text-gray-500">
                ${this.searchTerm ? "No auditionees match your search." :
                  (this.hideScheduled ? "Everyone available is already scheduled. Uncheck <span class='font-medium'>Hide already-scheduled</span> to see them, or switch to <span class='font-medium'>Everyone</span>." :
                   "No one is marked available for this session. Switch to <span class='font-medium'>Everyone</span> to see all auditionees.")}
            </div>`
        }
        this.resultsTarget.innerHTML = html
    }

    sectionHtml(title, list, inThis) {
        if (list.length === 0) return ""
        const rows = list.map(r => this.rowHtml(r, inThis)).join("")
        return `<div class="mb-5 last:mb-0">
            <div class="text-[11px] font-semibold text-gray-400 uppercase tracking-wide mb-2">${this.h(title)} <span class="text-gray-300">(${list.length})</span></div>
            <div class="space-y-1.5">${rows}</div>
        </div>`
    }

    rowHtml(r, inThis) {
        const added = inThis.has(String(r.id))
        const status = this.statusFor(r.id)
        const scheduledElsewhere = !added && this.scheduled.has(String(r.id))
        const avatar = r.headshot
            ? `<img src="${this.h(r.headshot)}" class="w-11 h-11 rounded-lg object-cover flex-shrink-0" alt="">`
            : `<div class="w-11 h-11 rounded-lg bg-gray-100 text-gray-700 flex items-center justify-center font-bold text-sm flex-shrink-0">${this.h(r.initials || "?")}</div>`

        const statusBadge =
            status === "available" ? `<span class="text-[10px] px-1.5 py-0.5 rounded-full bg-green-100 text-green-700 font-medium">Available</span>`
            : status === "unavailable" ? `<span class="text-[10px] px-1.5 py-0.5 rounded-full bg-red-100 text-red-700 font-medium">Unavailable</span>`
            : `<span class="text-[10px] px-1.5 py-0.5 rounded-full bg-gray-100 text-gray-500 font-medium">No response</span>`

        const flag = added
            ? `<span class="text-[10px] px-1.5 py-0.5 rounded-full bg-green-100 text-green-700 font-medium">In this session</span>`
            : scheduledElsewhere ? `<span class="text-[10px] px-1.5 py-0.5 rounded-full bg-amber-100 text-amber-700 font-medium">In another session</span>` : ""

        const right = added
            ? `<span class="inline-flex items-center gap-1 text-xs font-medium text-green-700 flex-shrink-0"><svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M16.704 4.153a.75.75 0 0 1 .143 1.052l-8 10.5a.75.75 0 0 1-1.127.075l-4.5-4.5a.75.75 0 0 1 1.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 0 1 1.05-.143Z" clip-rule="evenodd"/></svg>Added</span>`
            : `<span class="inline-flex items-center gap-1 text-xs font-medium text-pink-600 flex-shrink-0"><svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15"/></svg>Add</span>`

        const cls = added
            ? "w-full flex items-center gap-3 px-3 py-2.5 rounded-lg border border-green-200 bg-green-50/60 cursor-default text-left"
            : "w-full flex items-center gap-3 px-3 py-2.5 rounded-lg border border-gray-200 bg-white hover:border-pink-400 hover:bg-pink-50 transition cursor-pointer text-left"

        return `<button type="button" class="${cls}" data-request-id="${r.id}" ${added ? "disabled" : ""}>
            ${avatar}
            <span class="flex-1 min-w-0">
                <span class="flex items-center gap-2">
                    <span class="text-sm font-medium text-gray-900 truncate">${this.h(r.name || "(no name)")}</span>
                    ${statusBadge}${flag}
                </span>
                <span class="flex items-center gap-2 mt-1.5">${this.voteBar(r)}</span>
            </span>
            ${right}
        </button>`
    }

    // Compact, readable vote summary: a proportional bar + plain-language counts.
    voteBar(r) {
        const yes = r.yes || 0, no = r.no || 0, maybe = r.maybe || 0
        const total = yes + no + maybe
        if (total === 0) return `<span class="text-[11px] text-gray-400">No votes yet</span>`
        const pct = (n) => `${Math.round((n / total) * 100)}%`
        return `
            <span class="inline-flex h-1.5 w-24 rounded-full overflow-hidden bg-gray-100 flex-shrink-0" title="${yes} yes, ${no} no, ${maybe} not sure">
                <span class="bg-green-500" style="width:${pct(yes)}"></span>
                <span class="bg-rose-400" style="width:${pct(no)}"></span>
                <span class="bg-gray-300" style="width:${pct(maybe)}"></span>
            </span>
            <span class="text-[11px] text-gray-500 whitespace-nowrap">
                <span class="text-green-700 font-semibold">${yes}</span> yes · ${no} no · ${maybe} not sure
            </span>`
    }

    // ----- actions -----
    addRequest(requestId) {
        if (!requestId) return
        this.postJson(this.addUrlValue, { audition_request_id: requestId, audition_session_id: this.currentSessionId })
            .then(data => {
                if (!data) return
                this.applyResponse(data)
                if (this.inSession[this.currentSessionId]) this.inSession[this.currentSessionId].add(String(requestId))
                this.scheduled.add(String(requestId))
                this.renderList() // person drops out (hide-scheduled) or flips to "Added"
            })
    }

    removeAudition(btn) {
        const auditionId = btn.dataset.auditionId
        const sessionId = String(btn.dataset.sessionId)
        const requestId = btn.dataset.requestId
        if (!auditionId) return
        this.postJson(this.removeUrlValue, { audition_id: auditionId, audition_session_id: sessionId })
            .then(data => {
                if (!data) return
                this.applyResponse(data)
                if (requestId && this.inSession[sessionId]) this.inSession[sessionId].delete(String(requestId))
            })
    }

    // Swap the affected session's slots and refresh the cycle-wide scheduled set.
    applyResponse(data) {
        if (data.scheduled_request_ids) this.scheduled = new Set(data.scheduled_request_ids.map(String))
        if (data.session_id != null && data.session_slots_html != null) {
            const target = this.sessionSlotsTargets.find(t => t.dataset.sessionId === String(data.session_id))
            if (target) target.innerHTML = data.session_slots_html
        }
    }

    postJson(url, body) {
        const token = document.querySelector('meta[name="csrf-token"]')?.content
        // No Accept: application/json — these endpoints render .html partials via
        // render_to_string, so the request format must stay HTML. (render json:
        // still returns JSON regardless.) ui: "v2" gets the lightweight response.
        return fetch(url, {
            method: "POST",
            headers: { "Content-Type": "application/json", "X-CSRF-Token": token || "" },
            body: JSON.stringify({ ...body, ui: "v2" })
        }).then(r => {
            if (!r.ok) { console.error(`[audition-assign] ${url} failed: ${r.status}`); return null }
            return r.json()
        }).catch(e => { console.error(`[audition-assign] ${url} error`, e); return null })
    }

    // ----- modal plumbing -----
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
