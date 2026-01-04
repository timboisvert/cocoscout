import { Controller } from "@hotwired/stimulus"

// Handles the My Messages page interactions
export default class extends Controller {
  static targets = ["modal", "modalContent", "productionInput", "productionButton", "productionDisplay", "productionPrefix", "subjectInput"]

  openModal(event) {
    event.preventDefault()
    if (this.hasModalTarget) {
      this.modalTarget.classList.remove("hidden")
      document.body.classList.add("overflow-hidden")
    }
  }

  closeModal(event) {
    if (event) event.preventDefault()
    if (this.hasModalTarget) {
      this.modalTarget.classList.add("hidden")
      document.body.classList.remove("overflow-hidden")
    }
  }

  closeModalOnBackdrop(event) {
    // Only close if clicking directly on the backdrop (not the modal content)
    if (event.target === this.modalTarget) {
      this.closeModal(event)
    }
  }

  stopPropagation(event) {
    event.stopPropagation()
  }

  selectProduction(event) {
    event.preventDefault()
    const button = event.currentTarget
    const productionId = button.dataset.productionId
    const productionName = button.dataset.productionName
    const productionInitials = button.dataset.productionInitials

    // Update hidden input
    if (this.hasProductionInputTarget) {
      this.productionInputTarget.value = productionId
    }

    // Update display button
    if (this.hasProductionDisplayTarget) {
      this.productionDisplayTarget.innerHTML = `
        <div class="w-10 h-10 flex items-center justify-center flex-shrink-0 rounded bg-pink-100 text-pink-600 font-bold text-sm">
          ${productionInitials}
        </div>
        <div>
          <div class="text-sm font-medium text-gray-900">${productionName}</div>
        </div>
      `
    }

    // Show and update the prefix
    if (this.hasProductionPrefixTarget && this.hasSubjectInputTarget) {
      this.productionPrefixTarget.textContent = `[${productionName}]`
      this.productionPrefixTarget.classList.remove("hidden")
      this.productionPrefixTarget.classList.add("inline-flex")
      // Update subject input to have rounded right corners only
      this.subjectInputTarget.classList.remove("rounded-lg")
      this.subjectInputTarget.classList.add("rounded-r-lg")
    }

    // Close the dropdown
    const dropdownMenu = button.closest("[data-controller='dropdown']").querySelector("[data-dropdown-target='menu']")
    if (dropdownMenu) {
      dropdownMenu.classList.add("hidden")
    }
  }
}
