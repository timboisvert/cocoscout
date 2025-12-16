import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["specificSection", "managersList", "talentPoolList", "managersToggle", "talentPoolToggle"]

  connect() {
    // Show/hide on initial load based on selected radio
    this.updateVisibility()
  }

  toggleSpecific(event) {
    // Close all lists when any radio button is selected
    this.closeAllLists()
    this.updateVisibility()
  }

  toggleManagersList(event) {
    event.preventDefault()
    const isHidden = this.managersListTarget.classList.contains('hidden')

    // Close other lists first
    this.closeAllLists()

    if (isHidden) {
      this.managersListTarget.classList.remove('hidden')
      event.currentTarget.textContent = 'Hide'
    }
  }

  toggleTalentPoolList(event) {
    event.preventDefault()
    const isHidden = this.talentPoolListTarget.classList.contains('hidden')

    // Close other lists first
    this.closeAllLists()

    if (isHidden) {
      this.talentPoolListTarget.classList.remove('hidden')
      event.currentTarget.textContent = 'Hide'
    }
  }

  closeAllLists() {
    // Hide all expandable lists
    if (this.hasManagersListTarget) {
      this.managersListTarget.classList.add('hidden')
    }
    if (this.hasTalentPoolListTarget) {
      this.talentPoolListTarget.classList.add('hidden')
    }

    // Reset all toggle button text
    if (this.hasManagersToggleTarget) {
      this.managersToggleTarget.textContent = 'Show'
    }
    if (this.hasTalentPoolToggleTarget) {
      this.talentPoolToggleTarget.textContent = 'Show'
    }
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
