import { Controller } from "@hotwired/stimulus"

// Handles the My Messages page interactions
export default class extends Controller {
  static targets = ["modal", "modalContent", "productionInput", "productionButton", "productionDisplay", "productionPrefix", "subjectInput", "productionItem"]

  selectProduction(event) {
    event.preventDefault()
    const button = event.currentTarget
    const productionId = button.dataset.productionId

    // Build URL with production_id param (or without for unread view)
    const url = productionId
      ? `/my/messages?production_id=${productionId}`
      : '/my/messages'

    // Navigate with Turbo
    Turbo.visit(url)
  }

  selectOrganization(event) {
    event.preventDefault()
    const button = event.currentTarget
    const organizationId = button.dataset.organizationId

    // Build URL with organization_id param for shared forum mode
    const url = `/my/messages?organization_id=${organizationId}`

    // Navigate with Turbo
    Turbo.visit(url)
  }

  // Modal methods for the emails page
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

  selectProductionForEmail(event) {
    event.preventDefault()
    const button = event.currentTarget
    const productionId = button.dataset.productionId
    const productionName = button.dataset.productionName
    const productionInitials = button.dataset.productionInitials
    const productionLogoUrl = button.dataset.productionLogoUrl

    // Update hidden input
    if (this.hasProductionInputTarget) {
      this.productionInputTarget.value = productionId
    }

    // Update display button - show logo if available, otherwise initials
    if (this.hasProductionDisplayTarget) {
      const logoHtml = productionLogoUrl
        ? `<div class="w-10 h-10 flex items-center justify-center flex-shrink-0 rounded bg-gray-100">
             <img src="${productionLogoUrl}" alt="${productionName} logo" class="w-10 h-10 object-cover rounded">
           </div>`
        : `<div class="w-10 h-10 flex items-center justify-center flex-shrink-0 rounded bg-pink-100 text-pink-600 font-bold text-sm">
             ${productionInitials}
           </div>`

      this.productionDisplayTarget.innerHTML = `
        ${logoHtml}
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
