import { Controller } from "@hotwired/stimulus"

// The Sold elsewhere modal: each site lists only the ticket types it has
// numbers for. "Add a ticket type" adds the only type left straight away,
// offers the choice when there's more than one, and goes away once every
// type has a row. A removed row counts as zero when saved (the server treats
// a type missing from a site as nothing sold there).
export default class extends Controller {
    static targets = ["rowTemplate", "site"]
    static values = { tiers: Array }

    connect() {
        this.siteTargets.forEach(site => this.refresh(site))
    }

    add(event) {
        const site = this.site(event)
        const free = this.freeTiers(site)
        if (free.length === 0) return
        if (free.length === 1) return this.insert(site, free[0])

        const chooser = site.querySelector("[data-outside-sales-chooser]")
        chooser.querySelectorAll("[data-tier-chip]").forEach(chip => {
            chip.classList.toggle("hidden", !free.some(tier => String(tier.id) === chip.dataset.tierChip))
        })
        chooser.classList.remove("hidden")
    }

    pick(event) {
        const site = this.site(event)
        const tier = this.tiersValue.find(t => String(t.id) === event.currentTarget.dataset.tierId)
        if (tier) this.insert(site, tier)
    }

    remove(event) {
        const site = this.site(event)
        event.currentTarget.closest("[data-tier-id]").remove()
        this.refresh(site)
    }

    insert(site, tier) {
        const html = this.rowTemplateTarget.innerHTML
            .replaceAll("__SOURCE__", site.dataset.source)
            .replaceAll("__TIER__", String(tier.id))
            .replaceAll("__TIER_NAME__", this.escape(tier.name))
        site.querySelector("[data-outside-sales-rows]").insertAdjacentHTML("beforeend", html)
        site.querySelector("[data-outside-sales-chooser]").classList.add("hidden")
        this.refresh(site)
        const input = site.querySelector(`[data-tier-id="${tier.id}"] input[type="number"]`)
        if (input) input.focus()
    }

    refresh(site) {
        site.querySelector("[data-outside-sales-add]").classList.toggle("hidden", this.freeTiers(site).length === 0)
    }

    freeTiers(site) {
        const present = [...site.querySelectorAll("[data-outside-sales-rows] [data-tier-id]")].map(row => row.dataset.tierId)
        return this.tiersValue.filter(tier => !present.includes(String(tier.id)))
    }

    site(event) {
        return event.currentTarget.closest("[data-outside-sales-site]")
    }

    escape(text) {
        return String(text).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))
    }
}
