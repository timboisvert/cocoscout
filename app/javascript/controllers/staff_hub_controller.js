import { Controller } from "@hotwired/stimulus"

// Client-side search for the staffing roster. Filters staff rows by
// name/email/title and shows an empty state when nothing matches.
export default class extends Controller {
    static targets = ["search", "item", "empty"]

    search() {
        const q = (this.hasSearchTarget ? this.searchTarget.value : "").trim().toLowerCase()
        let visible = 0
        this.itemTargets.forEach(item => {
            const hay = item.dataset.search || ""
            const match = q.length === 0 || hay.includes(q)
            item.classList.toggle("hidden", !match)
            if (match) visible++
        })
        if (this.hasEmptyTarget) {
            this.emptyTarget.classList.toggle("hidden", visible !== 0 || this.itemTargets.length === 0)
        }
    }
}
