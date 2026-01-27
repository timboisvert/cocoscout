import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["customName", "list", "servicesJson", "checkbox"]
    static values = { existing: Array }

    connect() {
        this.services = this.existingValue || []
        this.renderList()
    }

    toggleService(event) {
        const checkbox = event.currentTarget
        const name = checkbox.dataset.name
        const description = checkbox.dataset.description

        if (checkbox.checked) {
            this.services.push({ name, description, custom: false })
        } else {
            this.services = this.services.filter(s => s.name !== name)
        }

        this.renderList()
        this.updateHiddenField()
    }

    addCustom() {
        const name = this.customNameTarget.value.trim()
        if (!name) {
            alert("Please enter a service name")
            return
        }

        if (this.services.some(s => s.name.toLowerCase() === name.toLowerCase())) {
            alert("This service is already added")
            return
        }

        this.services.push({ name, description: "", custom: true })
        this.customNameTarget.value = ""
        this.renderList()
        this.updateHiddenField()
    }

    removeService(event) {
        const index = parseInt(event.currentTarget.dataset.index)
        this.services.splice(index, 1)
        this.renderList()
        this.updateHiddenField()
    }

    renderList() {
        if (this.services.length === 0) {
            this.listTarget.innerHTML = `
        <h3 class="text-sm font-medium text-gray-900 mb-2">Selected Services</h3>
        <p class="text-gray-500 text-sm">No services selected. This step is optional.</p>
      `
            return
        }

        this.listTarget.innerHTML = `
      <h3 class="text-sm font-medium text-gray-900 mb-2">Selected Services (${this.services.length})</h3>
      <div class="space-y-2">
        ${this.services.map((service, index) => `
          <div class="flex items-center justify-between p-2 bg-gray-50 rounded-lg">
            <div class="flex items-center gap-2">
              <svg class="w-4 h-4 text-green-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
              </svg>
              <span class="text-sm text-gray-900">${service.name}</span>
              ${service.custom ? '<span class="text-xs text-gray-400">(custom)</span>' : ''}
            </div>
            <button type="button" data-action="click->contract-services#removeService" data-index="${index}" class="text-red-500 hover:text-red-700">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        `).join("")}
      </div>
    `
    }

    updateHiddenField() {
        this.servicesJsonTarget.value = JSON.stringify(this.services)
    }
}
