import { Controller } from "@hotwired/stimulus"

// Controls inline talent pool management with modals
export default class extends Controller {
  static targets = [
    "membersList",
    "addModal",
    "removeModal",
    "searchInput",
    "searchResults",
    "removePersonName",
    "removeWarning"
  ]

  static values = {
    searchUrl: String,
    addPersonUrl: String,
    addGroupUrl: String,
    removePersonUrl: String,
    removeGroupUrl: String,
    membersUrl: String
  }

  connect() {
    this.pendingRemoval = null
  }

  // Add Modal
  openAddModal(event) {
    event.preventDefault()
    this.addModalTarget.classList.remove("hidden")
    this.searchInputTarget.focus()
    this.searchResultsTarget.innerHTML = ""
  }

  closeAddModal(event) {
    if (event) event.preventDefault()
    this.addModalTarget.classList.add("hidden")
    this.searchInputTarget.value = ""
    this.searchResultsTarget.innerHTML = ""
  }

  stopPropagation(event) {
    event.stopPropagation()
  }

  async search(event) {
    const query = event.target.value.trim()

    if (query.length < 2) {
      this.searchResultsTarget.innerHTML = '<p class="text-gray-500 text-sm p-4">Type at least 2 characters to search...</p>'
      return
    }

    this.searchResultsTarget.innerHTML = '<div class="flex justify-center p-4"><div class="animate-spin rounded-full h-6 w-6 border-b-2 border-pink-500"></div></div>'

    try {
      const response = await fetch(`${this.searchUrlValue}?query=${encodeURIComponent(query)}`, {
        headers: {
          "Accept": "text/html",
          "X-Requested-With": "XMLHttpRequest"
        }
      })

      if (response.ok) {
        const html = await response.text()
        this.searchResultsTarget.innerHTML = html
      } else {
        this.searchResultsTarget.innerHTML = '<p class="text-red-500 text-sm p-4">Error searching. Please try again.</p>'
      }
    } catch (error) {
      console.error("Search error:", error)
      this.searchResultsTarget.innerHTML = '<p class="text-red-500 text-sm p-4">Error searching. Please try again.</p>'
    }
  }

  async addMember(event) {
    event.preventDefault()
    const button = event.currentTarget
    const memberId = button.dataset.memberId
    const memberType = button.dataset.memberType

    button.disabled = true
    button.innerHTML = '<div class="animate-spin rounded-full h-4 w-4 border-b-2 border-white"></div>'

    const url = memberType === "Group" ? this.addGroupUrlValue : this.addPersonUrlValue

    try {
      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "text/html",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
          "X-Requested-With": "XMLHttpRequest"
        },
        body: JSON.stringify(memberType === "Group" ? { group_id: memberId } : { person_id: memberId })
      })

      if (response.ok) {
        await this.refreshMembersList()
        this.closeAddModal()
        this.showNotice("Added to talent pool")
      } else {
        button.disabled = false
        button.textContent = "Add"
        this.showError("Failed to add member. Please try again.")
      }
    } catch (error) {
      console.error("Add member error:", error)
      button.disabled = false
      button.textContent = "Add"
      this.showError("Failed to add member. Please try again.")
    }
  }

  // Remove Modal
  async openRemoveModal(event) {
    event.preventDefault()
    const button = event.currentTarget
    const personId = button.dataset.personId
    const memberType = button.dataset.memberType
    const memberName = button.dataset.memberName

    this.pendingRemoval = { id: personId, type: memberType, name: memberName }
    this.removePersonNameTarget.textContent = memberName
    this.removeWarningTarget.innerHTML = '<div class="flex justify-center"><div class="animate-spin rounded-full h-5 w-5 border-b-2 border-gray-500"></div></div>'

    this.removeModalTarget.classList.remove("hidden")

    // Fetch assignment info
    try {
      const baseUrl = this.removePersonUrlValue.replace(/\/remove_person$/, '')
      const response = await fetch(`${baseUrl}/upcoming_assignments/${personId}?member_type=${memberType}`, {
        headers: {
          "Accept": "application/json",
          "X-Requested-With": "XMLHttpRequest"
        }
      })

      if (response.ok) {
        const data = await response.json()
        if (data.assignments && data.assignments.length > 0) {
          this.removeWarningTarget.innerHTML = `
            <div class="bg-amber-50 border border-amber-200 rounded-lg p-3 text-amber-800 text-sm">
              <strong>Warning:</strong> ${memberName} is assigned to ${data.assignments.length} upcoming show${data.assignments.length > 1 ? 's' : ''}.
              Removing them from the talent pool will also remove these assignments.
            </div>
          `
        } else {
          this.removeWarningTarget.innerHTML = ''
        }
      } else {
        this.removeWarningTarget.innerHTML = ''
      }
    } catch (error) {
      console.error("Fetch assignments error:", error)
      this.removeWarningTarget.innerHTML = ''
    }
  }

  closeRemoveModal(event) {
    if (event) event.preventDefault()
    this.removeModalTarget.classList.add("hidden")
    this.pendingRemoval = null
  }

  async confirmRemove(event) {
    event.preventDefault()

    if (!this.pendingRemoval) return

    const button = event.currentTarget
    button.disabled = true
    button.innerHTML = '<div class="animate-spin rounded-full h-4 w-4 border-b-2 border-white inline-block mr-2"></div>Removing...'

    const url = this.pendingRemoval.type === "Group" ? this.removeGroupUrlValue : this.removePersonUrlValue

    try {
      const body = this.pendingRemoval.type === "Group"
        ? { group_id: this.pendingRemoval.id }
        : { person_id: this.pendingRemoval.id }

      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
          "X-Requested-With": "XMLHttpRequest"
        },
        body: JSON.stringify(body)
      })

      if (response.ok) {
        const memberName = this.pendingRemoval.name
        this.closeRemoveModal()
        await this.refreshMembersList()
        this.showNotice(`Removed ${memberName} from talent pool`)
      } else {
        button.disabled = false
        button.textContent = "Remove"
        this.showError("Failed to remove member. Please try again.")
      }
    } catch (error) {
      console.error("Remove member error:", error)
      button.disabled = false
      button.textContent = "Remove"
      this.showError("Failed to remove member. Please try again.")
    }
  }

  async refreshMembersList() {
    try {
      const response = await fetch(this.membersUrlValue, {
        headers: {
          "Accept": "text/html",
          "X-Requested-With": "XMLHttpRequest"
        }
      })

      if (response.ok) {
        const html = await response.text()
        this.membersListTarget.innerHTML = html
      }
    } catch (error) {
      console.error("Refresh members error:", error)
    }
  }

  showNotice(message) {
    // Remove any existing notices first
    document.querySelectorAll('[data-controller="notice"]').forEach(el => el.remove())

    const flash = document.createElement('div')
    flash.setAttribute('data-controller', 'notice')
    flash.setAttribute('data-notice-timeout-value', '2000')
    flash.setAttribute('data-notice-target', 'container')
    flash.className = 'fixed top-0 left-1/2 transform -translate-x-1/2 z-50 w-auto max-w-lg px-6 py-3 bg-pink-500 text-white shadow-lg flex items-center transition-opacity duration-300 rounded-bl-lg rounded-br-lg'
    flash.innerHTML = `<span class="font-medium">${message}</span>`
    document.body.appendChild(flash)
  }

  showError(message) {
    // Remove any existing notices first
    document.querySelectorAll('[data-controller="notice"]').forEach(el => el.remove())

    const flash = document.createElement('div')
    flash.setAttribute('data-controller', 'notice')
    flash.setAttribute('data-notice-timeout-value', '5000')
    flash.setAttribute('data-notice-target', 'container')
    flash.className = 'fixed top-0 left-1/2 transform -translate-x-1/2 z-50 w-auto max-w-lg px-6 py-3 bg-red-600 text-white shadow-lg flex items-center transition-opacity duration-300 rounded-bl-lg rounded-br-lg'
    flash.innerHTML = `<span class="font-medium">${message}</span>`
    document.body.appendChild(flash)
  }
}
