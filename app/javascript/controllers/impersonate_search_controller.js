import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "results", "spinner"]

  connect() {
    this.timeout = null
  }

  search() {
    clearTimeout(this.timeout)

    const query = this.inputTarget.value.trim()

    if (query.length < 2) {
      this.hideResults()
      return
    }

    this.spinnerTarget.classList.remove("hidden")

    // Debounce the search
    this.timeout = setTimeout(() => {
      this.performSearch(query)
    }, 300)
  }

  async performSearch(query) {
    try {
      const response = await fetch(`/superadmin/search_users?q=${encodeURIComponent(query)}`, {
        headers: {
          "Accept": "application/json",
          "X-Requested-With": "XMLHttpRequest"
        }
      })

      if (!response.ok) throw new Error("Search failed")

      const users = await response.json()
      this.renderResults(users)
    } catch (error) {
      console.error("Search error:", error)
      this.renderError()
    } finally {
      this.spinnerTarget.classList.add("hidden")
    }
  }

  renderResults(users) {
    const container = this.resultsTarget.querySelector("div")

    if (users.length === 0) {
      container.innerHTML = `
        <div class="p-3 text-sm text-gray-500 text-center">
          No users found
        </div>
      `
      this.showResults()
      return
    }

    container.innerHTML = users.map(user => `
      <form action="/superadmin/impersonate" method="post" class="block">
        <input type="hidden" name="authenticity_token" value="${this.getCSRFToken()}">
        <input type="hidden" name="email" value="${this.escapeHtml(user.email)}">
        <button type="submit" class="w-full text-left p-3 hover:bg-pink-50 transition-colors cursor-pointer flex items-center gap-3">
          <div class="w-8 h-8 rounded-full bg-gray-200 flex items-center justify-center flex-shrink-0">
            <span class="text-xs font-semibold text-gray-600">${this.escapeHtml(user.name.charAt(0).toUpperCase())}</span>
          </div>
          <div class="min-w-0 flex-1">
            <div class="font-medium text-sm text-gray-900 truncate">${this.escapeHtml(user.name)}</div>
            <div class="text-xs text-gray-500 truncate">${this.escapeHtml(user.email)}${user.public_key ? ` · ${this.escapeHtml(user.public_key)}` : ''}</div>
          </div>
          <svg class="w-4 h-4 text-gray-400 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
          </svg>
        </button>
      </form>
    `).join("")

    this.showResults()
  }

  renderError() {
    const container = this.resultsTarget.querySelector("div")
    container.innerHTML = `
      <div class="p-3 text-sm text-red-500 text-center">
        Search failed. Please try again.
      </div>
    `
    this.showResults()
  }

  showResults() {
    this.resultsTarget.classList.remove("hidden")
  }

  hideResults() {
    this.resultsTarget.classList.add("hidden")
  }

  getCSRFToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ""
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
