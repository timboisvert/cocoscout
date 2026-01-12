import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "moveModal",
    "productionsList",
    "targetProductionId",
    "moveButton",
    "moveForm",
    "warningBox",
    "warningText"
  ]

  static values = {
    productions: Array,
    warning: String
  }

  connect() {
    this.selectedProductionId = null
  }

  openMoveModal(event) {
    event.preventDefault()
    this.moveModalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
    this.renderProductions()

    if (this.warningValue) {
      this.warningTextTarget.textContent = this.warningValue
      this.warningBoxTarget.classList.remove("hidden")
    }
  }

  closeMoveModal(event) {
    if (event) event.preventDefault()
    this.moveModalTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  stopPropagation(event) {
    event.stopPropagation()
  }

  renderProductions() {
    const productions = this.productionsValue

    if (!productions || productions.length === 0) {
      this.productionsListTarget.innerHTML = `
        <p class="text-sm text-gray-500 text-center py-4">No other productions available.</p>
      `
      return
    }

    const html = productions.map(prod => `
      <label class="flex items-center gap-3 p-3 rounded-lg border border-gray-200 hover:border-pink-300 hover:bg-pink-50 cursor-pointer transition-colors production-option" data-production-id="${prod.id}">
        <input type="radio" name="production_selection" value="${prod.id}" class="h-4 w-4 text-pink-600 border-gray-300 focus:ring-pink-500 accent-pink-600" data-action="change->sign-up-form-actions#selectProduction">
        <div class="flex-1 min-w-0">
          <p class="font-medium text-gray-900 truncate">${this.escapeHtml(prod.name)}</p>
          <p class="text-xs text-gray-500">${prod.show_count} shows</p>
        </div>
        ${prod.logo_url ? `<img src="${prod.logo_url}" alt="" class="w-8 h-8 rounded object-cover flex-shrink-0">` : ''}
      </label>
    `).join('')

    this.productionsListTarget.innerHTML = html
  }

  selectProduction(event) {
    this.selectedProductionId = event.target.value
    this.targetProductionIdTarget.value = this.selectedProductionId
    this.moveButtonTarget.disabled = false

    // Update visual selection
    this.productionsListTarget.querySelectorAll('.production-option').forEach(el => {
      if (el.dataset.productionId === this.selectedProductionId) {
        el.classList.add('border-pink-500', 'bg-pink-50')
        el.classList.remove('border-gray-200')
      } else {
        el.classList.remove('border-pink-500', 'bg-pink-50')
        el.classList.add('border-gray-200')
      }
    })
  }

  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}
