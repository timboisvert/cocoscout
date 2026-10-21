import { Controller } from "@hotwired/stimulus"

// The shared People Picker (V1.1 plan §5; shared/_people_picker): a sheet
// that finds people and names a pick. It opens on a people-picker:open
// window event ({ id, title, context, params }) and dispatches
// people-picker:pick on its element for each tap, with the context the
// opener passed, so the page does what it always did with the pick.
export default class extends Controller {
    static targets = ["input", "results", "spinner", "inviteName", "guestName", "guestEmail"]
    static values = { id: String, url: String, params: Object, multi: Boolean }

    connect() {
        this.openContext = {}
        this.extraParams = {}
        this.picked = new Set()
    }

    open(event) {
        const detail = (event && event.detail) || {}
        if (detail.id && detail.id !== this.idValue) return
        this.openContext = detail.context || {}
        this.extraParams = detail.params || {}
        this.picked = new Set()
        const title = document.getElementById(`${this.idValue}-title`)
        if (title && detail.title) title.textContent = detail.title
        this.inputTarget.value = ""
        this.resultsTarget.innerHTML = '<p class="text-sm text-gray-400 text-center py-6">Type a name to find someone.</p>'
        this.sheet()?.classList.remove("hidden")
        if (this.listsFirst()) this.fetchResults("")
        else setTimeout(() => this.inputTarget.focus(), 50)
    }

    // A casting page shows the talent pool before anything is typed.
    listsFirst() {
        return this.paramsValue.list === "pool" || this.extraParams.list === "pool"
    }

    close() {
        this.sheet()?.classList.add("hidden")
    }

    search() {
        clearTimeout(this.timer)
        const q = this.inputTarget.value.trim()
        if (q.length < 2 && !this.listsFirst()) {
            this.resultsTarget.innerHTML = '<p class="text-sm text-gray-400 text-center py-6">Type a name to find someone.</p>'
            return
        }
        this.timer = setTimeout(() => this.fetchResults(q.length < 2 ? "" : q), 250)
    }

    async fetchResults(q) {
        const url = new URL(this.urlValue, window.location.origin)
        Object.entries({ ...this.paramsValue, ...this.extraParams, q }).forEach(([key, value]) => {
            if (value === null || value === undefined) return
            if (Array.isArray(value)) value.forEach(v => url.searchParams.append(`${key}[]`, v))
            else url.searchParams.set(key, value)
        })
        if (this.hasSpinnerTarget) this.spinnerTarget.classList.remove("hidden")
        try {
            const response = await fetch(url, { headers: { Accept: "text/html", "X-Requested-With": "XMLHttpRequest" } })
            if (!response.ok) throw new Error(`Search failed: ${response.status}`)
            const typed = this.inputTarget.value.trim()
            if ((typed.length < 2 ? "" : typed) !== q) return
            this.resultsTarget.innerHTML = await response.text()
            this.markPicked()
        } catch (error) {
            console.error(error)
            this.resultsTarget.innerHTML = '<p class="text-sm text-red-600 text-center py-6">Couldn\'t search. Check your connection and try again.</p>'
        } finally {
            if (this.hasSpinnerTarget) this.spinnerTarget.classList.add("hidden")
        }
    }

    pick(event) {
        const button = event.currentTarget
        let data
        try { data = JSON.parse(button.dataset.pick) } catch { return }
        this.announce(data)
        if (this.multiValue) {
            this.picked.add(`${data.type}_${data.id}`)
            this.markPicked()
        } else {
            this.close()
        }
    }

    invite(event) {
        const email = event.currentTarget.dataset.email
        const name = this.hasInviteNameTarget ? this.inviteNameTarget.value.trim() : ""
        if (this.hasInviteNameTarget && !name) {
            this.inviteNameTarget.focus()
            return
        }
        this.announce({ invite: true, email, name })
        this.close()
    }

    // A guest by name (and email), for pages that take one.
    guest() {
        const name = this.hasGuestNameTarget ? this.guestNameTarget.value.trim() : ""
        const email = this.hasGuestEmailTarget ? this.guestEmailTarget.value.trim() : ""
        if (!name) {
            this.guestNameTarget?.focus()
            return
        }
        this.announce({ guest: true, name, email })
        this.close()
    }

    announce(data) {
        this.element.dispatchEvent(new CustomEvent("people-picker:pick", {
            bubbles: true, detail: { ...data, context: this.openContext, picker: this.idValue }
        }))
    }

    // Multi: rows already picked read "Added" and stay put.
    markPicked() {
        this.resultsTarget.querySelectorAll("[data-people-picker-row]").forEach(row => {
            if (!this.picked.has(row.dataset.peoplePickerRow)) return
            row.disabled = true
            row.classList.add("opacity-60", "cursor-default", "bg-gray-50")
            row.classList.remove("cursor-pointer", "hover:bg-pink-50")
            row.querySelector("svg:last-child")?.remove()
            if (!row.querySelector("[data-people-picker-taken]")) {
                row.insertAdjacentHTML("beforeend", '<span class="text-xs text-gray-500 flex-shrink-0" data-people-picker-taken>Added</span>')
            }
        })
    }

    sheet() {
        return document.getElementById(this.idValue)
    }
}
