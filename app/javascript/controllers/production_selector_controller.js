import { Controller } from "@hotwired/stimulus"

// Drives the production picker (shared/production_selector). Long lists open
// with only the search box and the recently-used section; the full list sits
// behind the "Show all productions" button. Typing reveals the full list
// (filtered per keystroke) and hides recents; clearing the search restores
// whichever state the user was in. Rows are submit buttons, so choosing a
// production needs no JS.
export default class extends Controller {
  static targets = ["search", "row", "recents", "allList", "showAll", "empty"]

  showAll() {
    this.expanded = true
    if (this.hasAllListTarget) this.allListTarget.style.display = ""
    if (this.hasShowAllTarget) this.showAllTarget.style.display = "none"
  }

  filter() {
    const query = this.searchTarget.value.trim().toLowerCase()

    if (this.hasRecentsTarget) {
      this.recentsTarget.style.display = query ? "none" : ""
    }

    // Searching reveals the full (filtered) list; clearing it collapses the
    // list again unless the user had expanded it themselves.
    if (!this.expanded) {
      if (this.hasAllListTarget) this.allListTarget.style.display = query ? "" : "none"
      if (this.hasShowAllTarget) this.showAllTarget.style.display = query ? "none" : ""
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
