import { Controller } from "@hotwired/stimulus"

// Tabs for the staff edit modal. Details/Job/Roles share one save form; the
// Onboarding, Availability, Taxes and Danger Zone tabs have their own actions, so the Save
// footer is hidden on those.
export default class extends Controller {
    static targets = ["tab", "panel", "saveFooter"]
    static FOOTERLESS = ["onboarding", "availability", "taxes", "danger"]

    connect() {
        // A #tab in the URL (e.g. back from a Taxes-tab action) opens that tab.
        const fromHash = window.location.hash.slice(1)
        const known = this.tabTargets.some(t => t.dataset.tab === fromHash)
        this.switchTo(known ? fromHash : (this.tabTargets[0]?.dataset.tab || "details"))
    }

    switch(event) {
        if (event) event.preventDefault()
        this.switchTo(event.currentTarget.dataset.tab)
    }

    switchTo(key) {
        this.tabTargets.forEach(t => {
            const active = t.dataset.tab === key
            t.classList.toggle("border-pink-500", active)
            t.classList.toggle("text-pink-600", active)
            t.classList.toggle("border-transparent", !active)
            t.classList.toggle("text-gray-500", !active)
        })
        this.panelTargets.forEach(p => p.classList.toggle("hidden", p.dataset.panel !== key))
        if (this.hasSaveFooterTarget) {
            this.saveFooterTarget.classList.toggle("hidden", this.constructor.FOOTERLESS.includes(key))
        }
    }
}
