import { Controller } from "@hotwired/stimulus"

// Server-side draft for the Pay People form. Restores the saved snapshot on load
// and debounce-saves the whole form (grid fields, pulled-in entry ids, tips
// worksheet breakdowns) as you go. The server clears the draft once a run is paid.
export default class extends Controller {
    static targets = ["form"]
    static values = { url: String, initial: String }

    connect() {
        if (this.initialValue) {
            try { this.restore(JSON.parse(this.initialValue)) } catch (_) { /* ignore bad draft */ }
        }
    }

    schedule() {
        clearTimeout(this.timer)
        this.timer = setTimeout(() => this.save(), 800)
    }

    save() {
        const token = document.querySelector('meta[name="csrf-token"]')?.content
        fetch(this.urlValue, {
            method: "PATCH",
            headers: { "Content-Type": "application/json", "X-CSRF-Token": token, "Accept": "application/json" },
            body: JSON.stringify({ draft: JSON.stringify(this.serialize()) })
        }).catch(() => {})
    }

    serialize() {
        const form = this.formTarget
        // Note: payday is deliberately NOT persisted — a records date restored from
        // a days-old draft would show up stale/in the past. It always defaults to
        // today (server-set) instead.
        const out = { funding_method: this.val("funding_method"), lines: {} }
        form.querySelectorAll('[name^="lines["]').forEach(el => {
            const m = el.name.match(/^lines\[(\d+)\]\[([a-z_]+)\](\[\])?$/)
            if (!m) return
            const [, id, field, arr] = m
            out.lines[id] = out.lines[id] || {}
            if (arr) { (out.lines[id][field] = out.lines[id][field] || []).push(el.value) }
            else out.lines[id][field] = el.value
        })
        return out
    }

    restore(data) {
        if (!data) return
        const form = this.formTarget
        // payday intentionally not restored — keep the server default (today).
        if (data.funding_method) this.setVal("funding_method", data.funding_method)

        Object.entries(data.lines || {}).forEach(([id, fields]) => {
            Object.entries(fields).forEach(([field, val]) => {
                if (Array.isArray(val)) {
                    const holder = this.holderFor(id, field)
                    if (holder) {
                        holder.innerHTML = val
                            .map(v => `<input type="hidden" name="lines[${id}][${field}][]" value="${this.esc(v)}">`)
                            .join("")
                    }
                } else {
                    const input = form.querySelector(`[name="lines[${id}][${field}]"]`)
                    if (input) input.value = val
                }
            })
        })
        // Deferred a tick: this controller (outer wrapper) connects before
        // pay-hours (grid), and recalc's event must not fire until pay-hours
        // can price the restored entry ids into each row's workedCents —
        // otherwise pulled-in hours read as $0 in the totals until the next
        // input, which looks exactly like the draft losing them.
        setTimeout(() => this.recalc(), 0)
    }

    holderFor(id, field) {
        if (field === "time_entry_ids") return document.getElementById(`pay-entries-${id}`)
        if (field === "adhoc") return document.getElementById(`pay-adhoc-${id}`)
        if (field === "tips_sheet") return document.getElementById(`pay-tips-sheet-${id}`)
        if (field === "cash_tips_sheet") return document.getElementById(`pay-cashtips-sheet-${id}`)
        return null
    }

    recalc() {
        // One bubbling event re-runs totals, accordion summaries, and the Hours
        // and tips buttons' labels after a restore.
        const anyField = this.formTarget.querySelector('input[name^="lines["]')
        if (anyField) anyField.dispatchEvent(new Event("input", { bubbles: true }))
    }

    val(name) { const el = this.formTarget.querySelector(`[name="${name}"]`); return el ? el.value : "" }
    setVal(name, value) { const el = this.formTarget.querySelector(`[name="${name}"]`); if (el) el.value = value }
    esc(s) { return String(s == null ? "" : s).replace(/"/g, "&quot;") }
}
