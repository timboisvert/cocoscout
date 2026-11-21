import { Controller } from "@hotwired/stimulus"
import { markListItem, markSheetItem } from "controllers/lib/section_nav"

// The sections of a staff member's page: the side list's lines (tab) and the
// phone sheet's rows (sectionItem), each naming its panel in data-tab. Details/Job/Roles share one save form; the
// Onboarding, Availability, Taxes and Danger Zone tabs have their own actions, so the Save
// footer is hidden on those.
export default class extends Controller {
    static targets = ["tab", "panel", "saveFooter", "sectionItem", "sectionLabel"]
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

    // The name the shared section list and sheet call.
    select(event) { this.switch(event) }

    switchTo(key) {
        this.tabTargets.forEach(t => markListItem(t, t.dataset.tab === key))
        this.sectionItemTargets.forEach(item => {
            markSheetItem(item, item.dataset.tab === key, this.hasSectionLabelTarget ? this.sectionLabelTarget : null)
        })
        this.panelTargets.forEach(p => p.classList.toggle("hidden", p.dataset.panel !== key))
        if (this.hasSaveFooterTarget) {
            this.saveFooterTarget.classList.toggle("hidden", this.constructor.FOOTERLESS.includes(key))
        }
    }
}
