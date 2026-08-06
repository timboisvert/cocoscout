import { Controller } from "@hotwired/stimulus"

// The Hours modal on the Pay People grid. Each person's hours — approved time
// entries (checkbox = included in this pay) plus ad-hoc lines (hours + the role
// they were worked as, repeatable so different shifts at different roles each
// price at their own rate) — are picked here; the grid shows a pink button with
// what's included.
//
// Form truth lives per row: lines[id][time_entry_ids][] (entries holder) and
// lines[id][adhoc][] holding "hours|role_id" pairs (adhoc holder). "Done"
// commits the modal UI to those inputs; syncAll re-reads them (draft restore)
// back into the UI, row datasets, and button labels.
export default class extends Controller {
    static targets = ["row", "modal", "button", "pullModal", "pullCheckbox"]

    connect() {
        this.openModalEl = null
        this.syncAll()
    }

    // ---- open / close -------------------------------------------------------

    open(event) {
        const memberId = event.currentTarget.dataset.memberId
        const modal = this.modalFor(memberId)
        if (!modal) return
        this.syncRow(this.rowFor(memberId), { syncModalUi: true })
        this.openModalEl = modal
        modal.classList.remove("hidden")
        document.body.classList.add("overflow-hidden")
        this.recalcModal()
    }

    close() {
        if (this.openModalEl) this.openModalEl.classList.add("hidden")
        this.openModalEl = null
        document.body.classList.remove("overflow-hidden")
    }

    closeAll() {
        this.modalTargets.forEach(m => m.classList.add("hidden"))
        this.openModalEl = null
        document.body.classList.remove("overflow-hidden")
    }

    backdropClose(event) {
        if (event.target === this.openModalEl) this.close()
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    // ---- entry checkboxes ---------------------------------------------------

    selectAllEntries() {
        this.setAllEntries(true)
    }

    selectNoEntries() {
        this.setAllEntries(false)
    }

    setAllEntries(checked) {
        if (!this.openModalEl) return
        this.openModalEl.querySelectorAll("[data-entry-id]").forEach(cb => { cb.checked = checked })
        this.recalcModal()
    }

    // ---- ad-hoc lines -------------------------------------------------------

    addAdhocRow() {
        const modal = this.openModalEl
        const template = modal && this.q(modal, "adhocTemplate")
        if (!template) return
        this.q(modal, "adhocList").appendChild(template.content.cloneNode(true))
        this.updateRemoveButtons(modal)
        this.recalcModal()
    }

    removeAdhocRow(event) {
        const modal = this.openModalEl
        const row = event.target.closest("[data-adhoc-row]")
        if (!modal || !row) return
        const rows = this.adhocRows(modal)
        if (rows.length <= 1) {
            // Last line just clears instead of disappearing.
            const hours = row.querySelector("[data-adhoc-hours]")
            const select = row.querySelector("[data-adhoc-role]")
            if (hours) hours.value = ""
            if (select) select.value = ""
        } else {
            row.remove()
        }
        this.updateRemoveButtons(modal)
        this.recalcModal()
    }

    updateRemoveButtons(modal) {
        const rows = this.adhocRows(modal)
        rows.forEach(row => {
            const btn = row.querySelector("[data-adhoc-remove]")
            if (btn) btn.classList.toggle("invisible", rows.length <= 1)
        })
    }

    // ---- modal interactions -------------------------------------------------

    recalcModal() {
        const modal = this.openModalEl
        if (!modal) return
        const { hours, cents, needsRole } = this.modalState(modal)

        const total = this.q(modal, "modalTotal")
        if (total) total.textContent = `${this.fmtHours(hours)}h · ${this.fmtMoney(cents)}`

        // Ad-hoc subtotal box ("Additional hours · 3h · $45.00") + the amber
        // pick-a-role warning when a line has hours but no role yet.
        const adhoc = this.adhocState(modal)
        const summary = this.q(modal, "adhocSummary")
        const summaryValue = this.q(modal, "adhocSummaryValue")
        if (summary && summaryValue) {
            const show = adhoc.hours > 0 && !needsRole
            summary.classList.toggle("hidden", !show)
            if (show) summaryValue.textContent = `${this.fmtHours(adhoc.hours)}h · ${this.fmtMoney(adhoc.cents)}`
        }
        const hint = this.q(modal, "adhocHint")
        if (hint) {
            hint.classList.toggle("hidden", !needsRole)
            if (needsRole) hint.textContent = "Pick the role each line was worked as — that's what prices the hours."
        }

        const done = this.q(modal, "doneButton")
        if (done) done.disabled = needsRole
    }

    // Commit the open modal's UI to the row's hidden inputs, then close.
    done(event) {
        const modal = event.target.closest('[data-pay-hours-target="modal"]')
        if (!modal) return
        this.commit(modal.dataset.memberId)
        this.close()
        // One bubbling event refreshes totals, the accordion summary, and the draft.
        const holder = document.getElementById(`pay-adhoc-${modal.dataset.memberId}`)
        if (holder) holder.dispatchEvent(new Event("input", { bubbles: true }))
    }

    // ---- pay-confirm hook: commit specific members' modal UIs (used when the
    // missing-hours check adds entries by checking their boxes). ----
    commitMembers(event) {
        (event.detail?.memberIds || []).forEach(id => this.commit(id))
    }

    // ---- bulk pull ----------------------------------------------------------
    // "Pull in approved hours" writes nothing of its own: it ticks every entry
    // inside each chosen person's Hours modal and commits it, so the per-person
    // modals stay the only place that decides what's included and how it prices.
    // Ticking rather than replacing means hours already added by hand survive.

    openPull() {
        if (!this.hasPullModalTarget) return
        this.pullModalTarget.classList.remove("hidden")
        document.body.classList.add("overflow-hidden")
    }

    closePull() {
        if (!this.hasPullModalTarget) return
        this.pullModalTarget.classList.add("hidden")
        document.body.classList.remove("overflow-hidden")
    }

    pullSelectAll() {
        this.pullCheckboxTargets.forEach(cb => { cb.checked = true })
    }

    pullSelectNone() {
        this.pullCheckboxTargets.forEach(cb => { cb.checked = false })
    }

    pullConfirm() {
        const memberIds = this.pullCheckboxTargets.filter(cb => cb.checked).map(cb => cb.dataset.memberId)

        memberIds.forEach(memberId => {
            const modal = this.modalFor(memberId)
            if (!modal) return
            modal.querySelectorAll("[data-entry-id]").forEach(cb => { cb.checked = true })
            this.commit(memberId)
        })

        this.closePull()
        // One bubbling event refreshes totals, the accordion summary and the draft.
        const first = memberIds[0]
        const holder = first && document.getElementById(`pay-adhoc-${first}`)
        if (holder) holder.dispatchEvent(new Event("input", { bubbles: true }))
    }

    // ---- state sync ---------------------------------------------------------

    // Re-derive datasets + button labels from form truth (runs on any grid
    // input, including the draft restore). Skips the open modal's UI so we
    // never clobber in-progress edits.
    syncAll() {
        this.rowTargets.forEach(row => this.syncRow(row, { syncModalUi: this.openModalEl === null }))
    }

    syncRow(row, { syncModalUi } = { syncModalUi: false }) {
        if (!row) return
        const memberId = row.dataset.memberId
        const modal = this.modalFor(memberId)
        if (!modal) return

        const includedIds = this.holderValues(`pay-entries-${memberId}`)
        const adhocPairs = this.holderValues(`pay-adhoc-${memberId}`).map(v => this.parsePair(v))

        if (syncModalUi && modal !== this.openModalEl) {
            modal.querySelectorAll("[data-entry-id]").forEach(cb => { cb.checked = includedIds.includes(cb.dataset.entryId) })
            this.rebuildAdhocRows(modal, adhocPairs)
        }

        // Price it: checked entries at their own rates + each ad-hoc line at its role rate.
        let cents = 0
        let hours = 0
        includedIds.forEach(id => {
            const cb = modal.querySelector(`[data-entry-id="${id}"]`)
            if (!cb) return
            const h = parseFloat(cb.dataset.hours) || 0
            hours += h
            cents += Math.round((parseFloat(cb.dataset.rateCents) || 0) * h)
        })
        adhocPairs.forEach(pair => {
            if (pair.hours <= 0) return
            hours += pair.hours
            cents += Math.round(this.rateFor(modal, row, pair.roleId) * pair.hours)
        })

        row.dataset.workedCents = String(cents)
        row.dataset.workedHours = String(hours)
        const button = row.querySelector('[data-pay-hours-target="button"]')
        if (button) button.textContent = hours > 0 ? `${this.fmtHours(hours)}h · ${this.fmtMoney(cents)}` : "Add hours"
    }

    // Write the modal UI into the row's hidden inputs (the form truth).
    commit(memberId) {
        const modal = this.modalFor(memberId)
        const row = this.rowFor(memberId)
        if (!modal || !row) return

        const checkedIds = Array.from(modal.querySelectorAll("[data-entry-id]"))
            .filter(cb => cb.checked)
            .map(cb => cb.dataset.entryId)
        const entriesHolder = document.getElementById(`pay-entries-${memberId}`)
        if (entriesHolder) {
            entriesHolder.innerHTML = checkedIds
                .map(id => `<input type="hidden" name="lines[${memberId}][time_entry_ids][]" value="${id}">`)
                .join("")
        }

        const adhocHolder = document.getElementById(`pay-adhoc-${memberId}`)
        if (adhocHolder) {
            adhocHolder.innerHTML = this.adhocState(modal).lines
                .map(l => `<input type="hidden" name="lines[${memberId}][adhoc][]" value="${l.hours}|${l.roleId}">`)
                .join("")
        }

        this.syncRow(row, { syncModalUi: false })
    }

    // Match the modal's ad-hoc rows to the committed pairs (draft restore / reopen).
    rebuildAdhocRows(modal, pairs) {
        const list = this.q(modal, "adhocList")
        const template = this.q(modal, "adhocTemplate")
        if (!list) return

        const needed = Math.max(pairs.length, 1)
        let rows = this.adhocRows(modal)
        if (template) {
            while (rows.length > needed) { rows[rows.length - 1].remove(); rows = this.adhocRows(modal) }
            while (rows.length < needed) { list.appendChild(template.content.cloneNode(true)); rows = this.adhocRows(modal) }
        }
        rows = this.adhocRows(modal)
        rows.forEach((rowEl, i) => {
            const pair = pairs[i]
            const hours = rowEl.querySelector("[data-adhoc-hours]")
            const select = rowEl.querySelector("[data-adhoc-role]")
            if (hours) hours.value = pair && pair.hours > 0 ? pair.hours : ""
            if (select) select.value = pair ? pair.roleId : ""
        })
        this.updateRemoveButtons(modal)
    }

    // ---- helpers ------------------------------------------------------------

    modalState(modal) {
        let cents = 0
        let hours = 0
        modal.querySelectorAll("[data-entry-id]").forEach(cb => {
            if (!cb.checked) return
            const h = parseFloat(cb.dataset.hours) || 0
            hours += h
            cents += Math.round((parseFloat(cb.dataset.rateCents) || 0) * h)
        })
        const adhoc = this.adhocState(modal)
        hours += adhoc.hours
        cents += adhoc.cents
        return { hours, cents, needsRole: adhoc.needsRole }
    }

    // Read the ad-hoc lines straight from the modal UI.
    adhocState(modal) {
        const row = this.rowFor(modal.dataset.memberId)
        let hours = 0
        let cents = 0
        let needsRole = false
        const lines = []

        this.adhocRows(modal).forEach(rowEl => {
            const h = parseFloat(rowEl.querySelector("[data-adhoc-hours]")?.value || "0") || 0
            if (h <= 0) return
            const select = rowEl.querySelector("[data-adhoc-role]")
            const fixed = rowEl.querySelector("[data-adhoc-fixed]")
            const roleId = select ? select.value : (fixed?.dataset.roleId || "")
            if (select && !select.value) { needsRole = true; return }
            const lineCents = Math.round(this.rateFor(modal, row, roleId) * h)
            hours += h
            cents += lineCents
            lines.push({ hours: h, roleId })
        })

        return { hours, cents, needsRole, lines }
    }

    adhocRows(modal) {
        return Array.from(this.q(modal, "adhocList")?.querySelectorAll("[data-adhoc-row]") || [])
    }

    // Rate for one ad-hoc line: the chosen role's rate, the fixed single role's
    // rate, else the member default.
    rateFor(modal, row, roleId) {
        if (roleId) {
            const source = modal.querySelector(`[data-adhoc-role] option[value="${roleId}"], [data-adhoc-fixed][data-role-id="${roleId}"]`)
            if (source) return parseFloat(source.dataset.rateCents) || 0
        }
        return parseFloat(row?.dataset.rate || "0") || 0
    }

    parsePair(value) {
        const [hours, roleId] = String(value).split("|")
        return { hours: parseFloat(hours) || 0, roleId: roleId || "" }
    }

    holderValues(holderId) {
        const holder = document.getElementById(holderId)
        return holder ? Array.from(holder.querySelectorAll("input")).map(i => i.value) : []
    }

    rowFor(memberId) {
        return this.rowTargets.find(r => r.dataset.memberId === String(memberId))
    }

    modalFor(memberId) {
        return this.modalTargets.find(m => m.dataset.memberId === String(memberId))
    }

    q(modal, target) {
        return modal.querySelector(`[data-pay-hours-target="${target}"]`)
    }

    fmtHours(h) {
        return String(Math.round(h * 100) / 100)
    }

    fmtMoney(cents) {
        return "$" + (cents / 100).toFixed(2)
    }
}
