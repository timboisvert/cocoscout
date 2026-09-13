import { Controller } from "@hotwired/stimulus"
import { confirmDialog } from "controllers/lib/confirm_dialog"

// The casting-table board. Clicking a cell opens a panel rendered by the server
// (casting_tables#cell) showing that night's running order, who is in each slot
// and what this member already holds — the things you compare against when
// deciding what to give somebody.
//
// Every change is answered with fresh HTML for the cell and the panel plus the
// recounted tallies. The browser used to patch the cell's classes by hand and
// keep its own copy of the role counts, keyed by role NAME — which could not
// show a second act at all and mismatched the two same-named acts of an
// act-based lineup.
export default class extends Controller {
    static targets = ["cell", "roleSelector", "roleOptions", "showCount", "memberCount", "totalCount", "draftAssignmentCount"]
    static values = { tableId: Number }

    connect() {
        this.currentCell = null
        this.outsideClick = this.handleOutsideClick.bind(this)
        this.keydown = this.handleKeydown.bind(this)
        document.addEventListener("click", this.outsideClick)
        document.addEventListener("keydown", this.keydown)
    }

    disconnect() {
        document.removeEventListener("click", this.outsideClick)
        document.removeEventListener("keydown", this.keydown)
    }

    handleKeydown(event) {
        if (event.key === "Escape") this.closeRoleSelector()
    }

    handleOutsideClick(event) {
        if (this.roleSelectorTarget.classList.contains("hidden")) return
        if (this.roleSelectorTarget.contains(event.target)) return
        if (event.target.closest('[data-casting-table-target="cell"]')) return
        this.closeRoleSelector()
    }

    // --- opening the panel ----------------------------------------------------

    async openRoleSelector(event) {
        event.stopPropagation()
        const cell = event.target.closest('[data-casting-table-target="cell"]')
        if (!cell) return

        this.currentCell = cell
        this.roleOptionsTarget.innerHTML = '<div class="px-6 py-10 text-center text-sm text-gray-400">Loading…</div>'
        this.position(cell)
        this.roleSelectorTarget.classList.remove("hidden")

        const params = new URLSearchParams(this.cellParams(cell))
        try {
            const response = await fetch(`/manage/casting/tables/${this.tableIdValue}/cell?${params}`, {
                headers: { Accept: "application/json" }
            })
            const data = await response.json()
            if (!response.ok) {
                this.showPanelError(data.error)
                return
            }
            this.roleOptionsTarget.innerHTML = data.picker_html
            this.position(cell)
        } catch (error) {
            console.error(error)
            this.showPanelError("Couldn't load this cell. Check your connection and try again.")
        }
    }

    closeRoleSelector() {
        this.roleSelectorTarget.classList.add("hidden")
        this.currentCell = null
    }

    // --- assigning and removing ----------------------------------------------

    // One handler for both directions: a slot this member holds removes it, any
    // other slot adds it. The panel says which is which.
    async toggleSlot(event) {
        event.stopPropagation()
        const row = event.currentTarget
        const cell = this.currentCell
        if (!cell) return

        const roleId = row.dataset.roleId
        const held = row.dataset.held === "true"

        if (held) {
            this.send("DELETE", "unassign", { ...this.cellParams(cell), role_id: roleId })
            return
        }

        // A restricted role the member isn't eligible for still goes through —
        // the producer's call — but it asks first, in the app's own dialog rather
        // than a browser confirm.
        if (row.dataset.eligible === "false") {
            const ok = await confirmDialog({
                title: "Not on the eligible list",
                message: `${row.dataset.roleName} is restricted, and this member isn't on its list. Cast them anyway?`,
                confirmText: "Cast anyway"
            })
            if (!ok) return
        }

        this.send("POST", "assign", { ...this.cellParams(cell), role_id: roleId })
    }

    async send(method, path, body, { force = false } = {}) {
        const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
        const cell = this.currentCell

        try {
            const response = await fetch(`/manage/casting/tables/${this.tableIdValue}/${path}`, {
                method,
                headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken, Accept: "application/json" },
                body: JSON.stringify(force ? { ...body, force: true } : body)
            })
            const data = await response.json()

            // 409: the member is already busy that night. Same contract the show
            // board's conflict modal uses.
            if (response.status === 409 && data.conflicts) {
                const ok = await confirmDialog({
                    title: "Already booked that night",
                    message: `${data.conflicts.map((c) => c.message).join(" ")} Cast them anyway?`,
                    confirmText: "Cast anyway"
                })
                if (ok) this.send(method, path, body, { force: true })
                return
            }

            if (!response.ok) {
                this.showPanelError(data.error)
                return
            }

            this.applyRefresh(cell, data)
        } catch (error) {
            console.error(error)
            this.showPanelError("That didn't save. Check your connection and try again.")
        }
    }

    // Swap in what the server just rendered: the cell, the reopened panel, and
    // the tallies.
    applyRefresh(cell, data) {
        if (cell && data.cell_html) cell.innerHTML = data.cell_html
        if (data.picker_html) this.roleOptionsTarget.innerHTML = data.picker_html

        const showCell = this.showCountTargets.find((el) => el.dataset.showId === String(data.show_id))
        if (showCell) {
            showCell.dataset.currentCount = data.show_count
            showCell.dataset.totalSlots = data.show_total_slots
            const text = showCell.querySelector(".show-count-text")
            if (text) text.textContent = `${data.show_count}/${data.show_total_slots}`
            const tick = showCell.querySelector(".fully-cast-icon")
            if (tick) tick.classList.toggle("hidden", !data.show_fully_cast)
        }

        const memberCell = this.memberCountTargets.find((el) => el.dataset.memberKey === data.member_key)
        if (memberCell) {
            memberCell.dataset.currentCount = data.member_count
            const badge = memberCell.querySelector(".member-count-text")
            if (badge) {
                badge.textContent = data.member_count
                badge.classList.toggle("bg-pink-100", data.member_count > 0)
                badge.classList.toggle("text-pink-700", data.member_count > 0)
                badge.classList.toggle("bg-gray-100", data.member_count === 0)
                badge.classList.toggle("text-gray-500", data.member_count === 0)
            }
        }

        this.totalCountTargets.forEach((el) => {
            el.dataset.currentCount = data.total_count
            const slots = parseInt(el.dataset.totalSlots, 10) || 0
            const text = el.querySelector(".total-count-text")
            if (text) text.textContent = `${data.total_count}/${slots}`
        })
        this.draftAssignmentCountTargets.forEach((el) => { el.textContent = data.total_count })

        if (cell) this.position(cell)
    }

    // --- chrome --------------------------------------------------------------

    showPanelError(message) {
        const text = message || "Something went wrong."
        this.roleOptionsTarget.insertAdjacentHTML("afterbegin",
            `<div class="px-4 py-3 bg-amber-50 border-b border-amber-200 text-xs text-amber-800">${text}</div>`)
    }

    cellParams(cell) {
        return {
            show_id: cell.dataset.showId,
            assignable_type: cell.dataset.memberType,
            assignable_id: cell.dataset.memberId
        }
    }

    // Beside the cell when there's room, otherwise flipped or clamped — the panel
    // is a good deal taller than the old popup, so it has to stay on screen.
    position(cell) {
        const panel = this.roleSelectorTarget
        const rect = cell.getBoundingClientRect()
        const wasHidden = panel.classList.contains("hidden")
        if (wasHidden) panel.classList.remove("hidden")
        const { width, height } = panel.getBoundingClientRect()
        if (wasHidden) panel.classList.add("hidden")

        const margin = 8
        let left = rect.right + margin
        if (left + width > window.innerWidth - margin) left = rect.left - width - margin
        if (left < margin) left = Math.max(margin, (window.innerWidth - width) / 2)

        let top = rect.top
        if (top + height > window.innerHeight - margin) top = window.innerHeight - height - margin
        if (top < margin) top = margin

        panel.style.left = `${left}px`
        panel.style.top = `${top}px`
    }
}
