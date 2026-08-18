import { Controller } from "@hotwired/stimulus"

// Drives a checkbox list of productions that can get long (the "Who uses this
// calculation?" modal): a search box narrows rows by name, optional type chips
// narrow by production_type, and a counter reports how many are ticked. Rows
// use inline display (not the `hidden` class) so their layout classes can't win.
export default class extends Controller {
  static targets = ["search", "chip", "row", "empty", "count", "checkbox"]

  connect() {
    this.type = ""
    this.updateCount()
  }

  filter() {
    this.apply()
  }

  setType(event) {
    this.type = event.params.type || ""

    this.chipTargets.forEach(chip => {
      const active = (chip.dataset.productionChecklistTypeParam || "") === this.type
      chip.classList.toggle("bg-pink-500", active)
      chip.classList.toggle("text-white", active)
      chip.classList.toggle("border-pink-500", active)
      chip.classList.toggle("bg-white", !active)
      chip.classList.toggle("text-gray-700", !active)
      chip.classList.toggle("border-gray-300", !active)
    })

    this.apply()
  }

  updateCount() {
    if (!this.hasCountTarget) return
    const checked = this.checkboxTargets.filter(box => box.checked).length
    this.countTarget.textContent = checked === 1 ? "1 selected" : `${checked} selected`
  }

  apply() {
    const query = this.hasSearchTarget ? this.searchTarget.value.trim().toLowerCase() : ""

    let visible = 0
    this.rowTargets.forEach(row => {
      const nameMatch = !query || row.dataset.name.includes(query)
      const typeMatch = !this.type || row.dataset.type === this.type
      const match = nameMatch && typeMatch
      row.style.display = match ? "" : "none"
      if (match) visible++
    })

    if (this.hasEmptyTarget) {
      this.emptyTarget.style.display = visible === 0 && this.rowTargets.length > 0 ? "" : "none"
    }
  }
}
