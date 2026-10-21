import { Controller } from "@hotwired/stimulus"

// Click-to-add scheduling for audition sessions. Each session has an "Add"
// slot; it opens the shared People Picker ("audition-picker",
// shared/_people_picker), which lists the cycle's sign-ups marked available
// for that session first, by votes. Picking one POSTs to add_to_session and
// swaps the session's slots with fresh server HTML. Removing happens from
// an assigned card (handled here too).
export default class extends Controller {
    static targets = ["sessionSlots"]
    static values = {
        addUrl: String,
        removeUrl: String
    }

    // Delegated click on a session's slots: open the picker or remove a card.
    // Delegation keeps this working after the slots' innerHTML is swapped.
    slotsClick(event) {
        const removeBtn = event.target.closest("[data-audition-id]")
        if (removeBtn) { this.removeAudition(removeBtn); return }
        const addBtn = event.target.closest("[data-add-slot]")
        if (addBtn) this.open(addBtn)
    }

    open(btn) {
        this.currentSessionId = String(btn.dataset.sessionId)
        const label = btn.dataset.sessionLabel
        window.dispatchEvent(new CustomEvent("people-picker:open", {
            detail: { id: "audition-picker", title: label ? `Add to ${label}` : "Add auditionees",
                      context: { session_id: this.currentSessionId }, params: { audition_session_id: this.currentSessionId } }
        }))
    }

    // people-picker:pick: add the sign-up to the session.
    picked(event) {
        const pick = event.detail
        if (pick.picker !== "audition-picker" || !pick.requestId) return
        this.currentSessionId = String(pick.context.session_id || this.currentSessionId)
        this.addRequest(pick.requestId)
    }

    // ----- actions -----
    addRequest(requestId) {
        if (!requestId) return
        this.postJson(this.addUrlValue, { audition_request_id: requestId, audition_session_id: this.currentSessionId })
            .then(data => { if (data) this.applyResponse(data) })
    }

    removeAudition(btn) {
        const auditionId = btn.dataset.auditionId
        const sessionId = String(btn.dataset.sessionId)
        if (!auditionId) return
        this.postJson(this.removeUrlValue, { audition_id: auditionId, audition_session_id: sessionId })
            .then(data => { if (data) this.applyResponse(data) })
    }

    // Swap the affected session's slots.
    applyResponse(data) {
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
}
