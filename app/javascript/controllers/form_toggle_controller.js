import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="form-toggle"
export default class extends Controller {
  static targets = ["select", "section"]

  connect() {
    this.toggle()
  }

  toggle() {
    const selectedValue = this.selectTarget.value

    this.sectionTargets.forEach((section) => {
      const toggleValues = section.dataset.toggleValue.split(',')
      const shouldShow = toggleValues.some(value => selectedValue.includes(value.trim()))

      if (shouldShow) {
        section.classList.remove("hidden")
      } else {
        section.classList.add("hidden")
      }
    })
  }
}
