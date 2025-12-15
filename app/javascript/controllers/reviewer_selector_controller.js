import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["specificSection", "managersList", "talentPoolList"]

  connect() {
    // Show/hide on initial load based on selected radio
    this.updateVisibility()
  }

  toggleSpecific(event) {
    this.updateVisibility()
  }

  toggleManagersList(event) {
    event.preventDefault()
    this.managersListTarget.classList.toggle('hidden')
    event.currentTarget.textContent = this.managersListTarget.classList.contains('hidden') ? 'Show' : 'Hide'
  }

  toggleTalentPoolList(event) {
    event.preventDefault()
    this.talentPoolListTarget.classList.toggle('hidden')
    event.currentTarget.textContent = this.talentPoolListTarget.classList.contains('hidden') ? 'Show' : 'Hide'
  }

  updateVisibility() {
    const specificRadio = document.querySelector('input[name="reviewer_access_type"][value="specific"]')
    if (specificRadio && specificRadio.checked) {
      this.specificSectionTarget.classList.remove('hidden')
    } else {
      this.specificSectionTarget.classList.add('hidden')
    }
  }
}
