import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "results", "inviteForm", "inviteName", "inviteEmail", "searchSection", "selectedPerson", "selectedPersonName", "selectedPersonEmail", "selectedPersonIdInput", "personDetailsSection"]
  static values = { url: String }

  connect() {
    this.timeout = null
  }

  search() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {
      this.performSearch()
    }, 250)
  }

  performSearch() {
    const query = this.inputTarget.value.trim()
    if (query.length === 0) {
      this.resultsTarget.innerHTML = ""
      return
    }
    const url = `${this.urlValue}?q=${encodeURIComponent(query)}`
    fetch(url)
      .then(r => r.text())
      .then(html => {
        this.resultsTarget.innerHTML = html
      })
  }

  showInviteForm(event) {
    const email = event.currentTarget.dataset.email || ""
    
    // Hide search section, show invite form
    this.searchSectionTarget.classList.add("hidden")
    this.inviteFormTarget.classList.remove("hidden")
    
    // Show person details section for manual entry
    if (this.hasPersonDetailsSectionTarget) {
      this.personDetailsSectionTarget.classList.remove("hidden")
    }
    
    // Pre-fill email if provided
    if (email) {
      this.inviteEmailTarget.value = email
    }
    
    // Focus on name field
    this.inviteNameTarget.focus()
  }

  selectPerson(event) {
    const personId = event.currentTarget.dataset.personId
    const personName = event.currentTarget.dataset.personName
    const personEmail = event.currentTarget.dataset.personEmail
    
    // Hide search section, show selected person and invite form
    this.searchSectionTarget.classList.add("hidden")
    this.selectedPersonTarget.classList.remove("hidden")
    this.inviteFormTarget.classList.remove("hidden")
    
    // Hide the person details section (step 1) since we already have the person
    if (this.hasPersonDetailsSectionTarget) {
      this.personDetailsSectionTarget.classList.add("hidden")
    }
    
    // Set selected person info
    this.selectedPersonNameTarget.textContent = personName
    this.selectedPersonEmailTarget.textContent = personEmail
    this.selectedPersonIdInputTarget.value = personId
    
    // Pre-fill the name and email
    this.inviteNameTarget.value = personName
    this.inviteEmailTarget.value = personEmail
  }

  backToSearch() {
    // Show search section, hide others
    this.searchSectionTarget.classList.remove("hidden")
    this.inviteFormTarget.classList.add("hidden")
    this.selectedPersonTarget.classList.add("hidden")
    
    // Clear selected person
    if (this.hasSelectedPersonIdInputTarget) {
      this.selectedPersonIdInputTarget.value = ""
    }
    
    // Show person details section again
    if (this.hasPersonDetailsSectionTarget) {
      this.personDetailsSectionTarget.classList.remove("hidden")
    }
    
    // Focus back on search
    this.inputTarget.focus()
    this.inputTarget.select()
  }

  reset() {
    this.inputTarget.value = ""
    this.resultsTarget.innerHTML = ""
    this.inputTarget.focus()
  }
}
