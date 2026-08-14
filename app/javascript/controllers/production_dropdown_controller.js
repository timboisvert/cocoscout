import { Controller } from "@hotwired/stimulus"

// Type chips inside the wide production filter dropdown
// (shared/filters/production_dropdown_filter): narrow the production links to
// one production_type client-side. Rows use inline display (not the `hidden`
// class) so their layout classes can't win the fight.
export default class extends Controller {
  static targets = ["chip", "row", "empty"]

  setType(event) {
    const type = event.params.type || ""

    this.chipTargets.forEach(chip => {
      const active = (chip.dataset.productionDropdownTypeParam || "") === type
      chip.classList.toggle("bg-white", active)
      chip.classList.toggle("text-pink-600", active)
      chip.classList.toggle("bg-pink-600", !active)
      chip.classList.toggle("text-white", !active)
    })

    let visible = 0
    this.rowTargets.forEach(row => {
      const match = !type || row.dataset.type === type
      row.style.display = match ? "" : "none"
      if (match) visible++
    })

    if (this.hasEmptyTarget) {
      this.emptyTarget.style.display = visible === 0 ? "" : "none"
    }
  }
}
