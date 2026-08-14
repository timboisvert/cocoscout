import { Controller } from "@hotwired/stimulus"

// Type-to-filter for the production picker (shared/production_selector).
// Rows are submit buttons, so choosing needs no JS — this controller only
// narrows the "all productions" list as the user types and hides the
// recently-used section (its entries are duplicates of filtered rows).
export default class extends Controller {
  static targets = ["search", "row", "recents", "empty"]

  filter() {
    const query = this.searchTarget.value.trim().toLowerCase()

    if (this.hasRecentsTarget) {
      this.recentsTarget.style.display = query ? "none" : ""
    }

    let visible = 0
    this.rowTargets.forEach(row => {
      const match = !query || row.dataset.name.includes(query)
      row.style.display = match ? "" : "none"
      if (match) visible++
    })

    if (this.hasEmptyTarget) {
      this.emptyTarget.style.display = visible === 0 && this.rowTargets.length > 0 ? "" : "none"
    }
  }
}
