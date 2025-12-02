import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "results",
        "selectedContainer",
        "selectedName",
        "selectedHeadshot",
        "selectedInitials",
        "searchContainer",
        "shouteeType",
        "shouteeId",
        "inviteForm",
        "searchField",
        "contentField",
        "existingShoutoutNotice",
        "existingShoutoutName"
    ]

    connect() {
        this.timeout = null
        this.inviteMode = false
    }

    search(event) {
        const query = event.target.value.trim()

        // Clear previous timeout
        if (this.timeout) {
            clearTimeout(this.timeout)
        }

        if (query.length < 2) {
            this.resultsTarget.classList.add("hidden")
            return
        }

        // Debounce the search
        this.timeout = setTimeout(() => {
            fetch(`/my/shoutouts/search?q=${encodeURIComponent(query)}`)
                .then(response => response.json())
                .then(data => {
                    this.displayResults(data, query)
                })
                .catch(error => {
                    console.error("Search error:", error)
                })
        }, 300)
    }

    displayResults(data, query) {
        if (data.length === 0) {
            // Show the invite button option
            this.resultsTarget.innerHTML = `
      <button type="button"
        class="w-full flex items-center gap-3 p-3 hover:bg-pink-50 transition-colors text-left border-t-2 border-gray-200 cursor-pointer"
        data-action="click->shoutout-search#showInviteForm">
        <div class="w-10 h-10 rounded-lg bg-pink-100 flex items-center justify-center flex-shrink-0">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" class="w-5 h-5 text-pink-600">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
          </svg>
        </div>
        <div>
          <div class="font-medium text-pink-600">Invite someone to CocoScout</div>
          <div class="text-xs text-gray-500">Give a shoutout and invite them to join</div>
        </div>
      </button>
    `
            this.resultsTarget.classList.remove("hidden")
            return
        }

        const html = data.map(item => `
      <button type="button"
        class="w-full flex items-center gap-3 p-3 hover:bg-gray-50 transition-colors text-left border-b border-gray-200 cursor-pointer"
        data-action="click->shoutout-search#selectResult"
        data-type="${item.type}"
        data-id="${item.id}"
        data-name="${item.name}"
        data-public-key="${item.public_key}">
        ${item.headshot_url ?
                `<img src="${item.headshot_url}" class="w-10 h-10 rounded-lg object-cover flex-shrink-0" alt="${item.name}">` :
                `<div class="w-10 h-10 rounded-lg bg-gradient-to-br from-pink-400 to-purple-500 flex items-center justify-center text-white font-bold text-sm flex-shrink-0">
            ${item.initials}
          </div>`
            }
        <div>
          <div class="font-medium text-gray-900">${item.name}</div>
          <div class="text-xs text-gray-500">@${item.public_key}</div>
        </div>
      </button>
    `).join("") + `
      <button type="button"
        class="w-full flex items-center gap-3 p-3 hover:bg-pink-50 transition-colors text-left border-t-2 border-gray-200 cursor-pointer"
        data-action="click->shoutout-search#showInviteForm">
        <div class="w-10 h-10 rounded-lg bg-pink-100 flex items-center justify-center flex-shrink-0">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" class="w-5 h-5 text-pink-600">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
          </svg>
        </div>
        <div>
          <div class="font-medium text-pink-600">Invite someone to CocoScout</div>
          <div class="text-xs text-gray-500">Give a shoutout and invite them to join</div>
        </div>
      </button>
    `

        this.resultsTarget.innerHTML = html
        this.resultsTarget.classList.remove("hidden")
    }

    selectResult(event) {
        const button = event.currentTarget
        const type = button.dataset.type
        const id = button.dataset.id
        const name = button.dataset.name
        const headshotUrl = button.querySelector('img')?.src
        const initials = button.querySelector('.bg-gradient-to-br')?.textContent.trim()

        // Set hidden fields
        this.shouteeTypeTarget.value = type
        this.shouteeIdTarget.value = id

        // Update selected display
        this.selectedNameTarget.textContent = name

        // Show headshot or initials
        if (headshotUrl) {
            this.selectedHeadshotTarget.src = headshotUrl
            this.selectedHeadshotTarget.alt = name
            this.selectedHeadshotTarget.classList.remove("hidden")
            this.selectedInitialsTarget.classList.add("hidden")
        } else if (initials) {
            this.selectedInitialsTarget.textContent = initials
            this.selectedInitialsTarget.classList.remove("hidden")
            this.selectedHeadshotTarget.classList.add("hidden")
        }

        // Check for existing shoutout
        this.checkExistingShoutout(type, id, name)

        // Hide search container and show selected
        if (this.hasSearchContainerTarget) {
            this.searchContainerTarget.classList.add("hidden")
        }
        this.selectedContainerTarget.classList.remove("hidden")

        // Hide results
        this.resultsTarget.classList.add("hidden")

        // Clear search input
        if (this.hasSearchFieldTarget) {
            this.searchFieldTarget.value = ""
        }
    }

    async checkExistingShoutout(type, id, name) {
        try {
            const response = await fetch(`/my/shoutouts/check_existing?shoutee_type=${type}&shoutee_id=${id}`)
            const data = await response.json()

            if (data.has_existing_shoutout && this.hasExistingShoutoutNoticeTarget) {
                this.existingShoutoutNameTarget.textContent = name
                this.existingShoutoutNoticeTarget.classList.remove("hidden")
            } else if (this.hasExistingShoutoutNoticeTarget) {
                this.existingShoutoutNoticeTarget.classList.add("hidden")
            }
        } catch (error) {
            console.error("Error checking existing shoutout:", error)
        }
    }

    clearSelection(event) {
        event.preventDefault()

        // Clear hidden fields
        this.shouteeTypeTarget.value = ""
        this.shouteeIdTarget.value = ""

        // Show search container and hide selected display
        if (this.hasSearchContainerTarget) {
            this.searchContainerTarget.classList.remove("hidden")
        }
        this.selectedContainerTarget.classList.add("hidden")

        // Focus search input
        if (this.hasSearchFieldTarget) {
            this.searchFieldTarget.focus()
        }
    }

    showInviteForm(event) {
        event.preventDefault()

        // Hide search results
        this.resultsTarget.classList.add("hidden")

        // Hide search container
        if (this.hasSearchContainerTarget) {
            this.searchContainerTarget.classList.add("hidden")
        }

        // Clear search field
        if (this.hasSearchFieldTarget) {
            this.searchFieldTarget.value = ""
        }

        // Show invite form
        if (this.hasInviteFormTarget) {
            this.inviteFormTarget.classList.remove("hidden")

            // Make invite fields required
            const nameField = this.element.querySelector('input[name="invite_name"]')
            const emailField = this.element.querySelector('input[name="invite_email"]')
            if (nameField) nameField.required = true
            if (emailField) emailField.required = true
        }

        // Set invite mode
        this.inviteMode = true

        // Set hidden field to indicate invite
        this.shouteeTypeTarget.value = "invite"
    }

    cancelInvite(event) {
        event.preventDefault()

        // Hide invite form
        if (this.hasInviteFormTarget) {
            this.inviteFormTarget.classList.add("hidden")
        }

        // Show search container again
        if (this.hasSearchContainerTarget) {
            this.searchContainerTarget.classList.remove("hidden")
        }

        // Clear invite fields and remove required
        const nameField = this.element.querySelector('input[name="invite_name"]')
        const emailField = this.element.querySelector('input[name="invite_email"]')
        if (nameField) {
            nameField.value = ""
            nameField.required = false
        }
        if (emailField) {
            emailField.value = ""
            emailField.required = false
        }

        // Clear hidden fields
        this.shouteeTypeTarget.value = ""
        this.shouteeIdTarget.value = ""

        // Reset invite mode
        this.inviteMode = false

        // Focus search field
        if (this.hasSearchFieldTarget) {
            this.searchFieldTarget.focus()
        }
    }

    cancel(event) {
        event.preventDefault()

        // If in invite mode, cancel that
        if (this.inviteMode) {
            this.cancelInvite(event)
            return
        }

        // Otherwise redirect to given tab without form
        window.location.href = '/my/shoutouts?tab=given'
    }
}
