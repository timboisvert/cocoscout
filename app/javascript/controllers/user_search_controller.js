import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["input", "results", "selectedForm", "selectedName", "selectedEmail", "emailField", "nameField"]
    static values = { url: String }

    connect() {
        this.timeout = null
    }

    search() {
        clearTimeout(this.timeout)
        const query = this.inputTarget.value.trim()

        if (query.length < 2) {
            this.resultsTarget.classList.add("hidden")
            return
        }

        this.timeout = setTimeout(() => {
            this.fetchResults(query)
        }, 200)
    }

    async fetchResults(query) {
        try {
            const response = await fetch(`${this.urlValue}?q=${encodeURIComponent(query)}`)
            const results = await response.json()
            this.displayResults(results)
        } catch (error) {
            console.error("Search error:", error)
        }
    }

    displayResults(results) {
        if (results.length === 0) {
            this.resultsTarget.innerHTML = `
        <div class="p-3 text-sm text-gray-500">No users found</div>
      `
            this.resultsTarget.classList.remove("hidden")
            return
        }

        this.resultsTarget.innerHTML = results.map(user => `
      <button type="button"
              class="w-full text-left px-3 py-2 hover:bg-pink-50 cursor-pointer border-b border-gray-100 last:border-0"
              data-action="click->user-search#select"
              data-email="${user.email}"
              data-name="${user.name || ''}">
        <div class="text-sm font-medium text-gray-900">${user.name || user.email}</div>
        <div class="text-xs text-gray-500">${user.email}</div>
      </button>
    `).join("")

        this.resultsTarget.classList.remove("hidden")
    }

    select(event) {
        const email = event.currentTarget.dataset.email
        const name = event.currentTarget.dataset.name

        this.emailFieldTarget.value = email
        this.nameFieldTarget.value = name
        this.selectedNameTarget.textContent = name || email
        this.selectedEmailTarget.textContent = email

        this.inputTarget.value = ""
        this.resultsTarget.classList.add("hidden")
        this.selectedFormTarget.classList.remove("hidden")
    }

    clear() {
        this.emailFieldTarget.value = ""
        this.nameFieldTarget.value = ""
        this.selectedFormTarget.classList.add("hidden")
    }
}
