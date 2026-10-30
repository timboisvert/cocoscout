import { Controller } from "@hotwired/stimulus"

// "Good for" on the Issue a gift certificate form: "Any show" shows nothing
// more; "Only these" opens a checklist of productions. Ticking a production
// means every date of it; its "All dates" opens the dates on sale to tick
// some instead, and the row then reads "3 of 6 dates". Typing in the search
// box (long lists only) filters the productions.
export default class extends Controller {
    static targets = ["list", "search", "production", "all", "pick", "dates", "date", "email", "emailIt", "emailWho"]

    connect() {
        this.emailChanged()
    }

    choose(event) {
        this.listTarget.classList.toggle("hidden", event.target.value !== "some")
    }

    filter() {
        const query = this.searchTarget.value.trim().toLowerCase()
        this.productionTargets.forEach((row) => {
            row.classList.toggle("hidden", query !== "" && !row.dataset.name.includes(query))
        })
    }

    // The production's own box: off clears its dates too.
    toggleProduction(event) {
        const row = event.target.closest("[data-gift-scope-target='production']")
        if (!event.target.checked) {
            row.querySelectorAll("[data-gift-scope-target='date']").forEach((box) => { box.checked = false })
            row.querySelector("[data-gift-scope-target='dates']").classList.add("hidden")
        }
        this.relabel(row)
    }

    toggleDates(event) {
        const row = event.currentTarget.closest("[data-gift-scope-target='production']")
        row.querySelector("[data-gift-scope-target='dates']").classList.toggle("hidden")
        this.relabel(row)
    }

    // A date ticked puts its production in; the production's box stays on
    // with some dates, and means every date only when none are ticked.
    toggleDate(event) {
        const row = event.target.closest("[data-gift-scope-target='production']")
        if (event.target.checked) row.querySelector("[data-gift-scope-target='all']").checked = true
        this.relabel(row)
    }

    relabel(row) {
        const pick = row.querySelector("[data-gift-scope-target='pick']")
        const open = !row.querySelector("[data-gift-scope-target='dates']").classList.contains("hidden")
        const ticked = row.querySelectorAll("[data-gift-scope-target='date']:checked").length
        const total = Number(pick.dataset.total)
        const words = ticked > 0 ? `${ticked} of ${total} dates` : "All dates"
        pick.textContent = `${words} ${open ? "▾" : "▸"}`
    }

    emailChanged() {
        if (!this.hasEmailTarget || !this.hasEmailItTarget) return
        const has = this.emailTarget.value.trim() !== ""
        this.emailItTarget.disabled = !has
        this.emailItTarget.closest("label").classList.toggle("opacity-50", !has)
        if (this.hasEmailWhoTarget) this.emailWhoTarget.textContent = has ? this.emailTarget.value.trim() : "them"
    }
}
