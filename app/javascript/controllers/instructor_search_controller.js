import { Controller } from "@hotwired/stimulus"

// Handles instructor search with 3-tier results (org, global, invite)
// and selection persistence for the course wizard
export default class extends Controller {
    static targets = [
        "searchInput",
        "searchResults",
        "searchSection",
        "selectedSection",
        "selectedName",
        "selectedEmail",
        "selectedHeadshot",
        "personIdField",
        "inviteName",
        "inviteEmail",
        "inviteForm"
    ]

    static values = {
        searchUrl: String,
        inviteUrl: String
    }

    connect() {
        this.timeout = null
    }

    search() {
        clearTimeout(this.timeout)
        this.timeout = setTimeout(() => this.performSearch(), 250)
    }

    async performSearch() {
        const query = this.searchInputTarget.value.trim()

        if (query.length < 2) {
            this.searchResultsTarget.innerHTML = '<p class="text-gray-500 text-sm p-4">Type at least 2 characters to search...</p>'
            return
        }

        this.searchResultsTarget.innerHTML = '<div class="flex justify-center p-4"><div class="animate-spin rounded-full h-6 w-6 border-b-2 border-pink-500"></div></div>'

        try {
            const response = await fetch(`${this.searchUrlValue}?q=${encodeURIComponent(query)}`, {
                headers: { "Accept": "text/html", "X-Requested-With": "XMLHttpRequest" }
            })

            if (response.ok) {
                this.searchResultsTarget.innerHTML = await response.text()
            } else {
                this.searchResultsTarget.innerHTML = '<p class="text-red-500 text-sm p-4">Error searching. Please try again.</p>'
            }
        } catch (error) {
            console.error("Instructor search error:", error)
            this.searchResultsTarget.innerHTML = '<p class="text-red-500 text-sm p-4">Error searching. Please try again.</p>'
        }
    }

    selectPerson(event) {
        event.preventDefault()
        const button = event.currentTarget
        const personId = button.dataset.personId
        const personName = button.dataset.personName
        const personEmail = button.dataset.personEmail || ""

        this.setSelectedPerson(personId, personName, personEmail)
    }

    setSelectedPerson(personId, name, email) {
        // Set the hidden field
        this.personIdFieldTarget.value = personId

        // Update the selected person display
        this.selectedNameTarget.textContent = name
        this.selectedEmailTarget.textContent = email

        // Show initials in headshot area
        const initials = name.split(" ").map(n => n[0]).join("").substring(0, 2).toUpperCase()
        this.selectedHeadshotTarget.innerHTML = `
      <div class="w-12 h-12 rounded-lg bg-pink-100 flex items-center justify-center text-pink-700 font-bold text-sm flex-shrink-0">
        ${initials}
      </div>
    `

        // Toggle sections
        this.searchSectionTarget.classList.add("hidden")
        this.selectedSectionTarget.classList.remove("hidden")
    }

    changePerson(event) {
        event.preventDefault()
        this.personIdFieldTarget.value = ""
        this.searchInputTarget.value = ""
        this.searchResultsTarget.innerHTML = ""
        this.selectedSectionTarget.classList.add("hidden")
        this.searchSectionTarget.classList.remove("hidden")
        this.searchInputTarget.focus()
    }

    showInviteForm(event) {
        event.preventDefault()
        const email = event.currentTarget.dataset.email || ""
        // Scroll to invite form if it exists, or show the form
        if (this.hasInviteFormTarget) {
            this.inviteEmailTarget.value = email
            this.inviteFormTarget.scrollIntoView({ behavior: "smooth" })
        }
    }

    async invitePerson(event) {
        event.preventDefault()
        const name = this.inviteNameTarget.value.trim()
        const email = this.inviteEmailTarget.value.trim()

        if (!name || !email) {
            alert("Please enter both name and email.")
            return
        }

        const button = event.currentTarget
        button.disabled = true
        const originalText = button.textContent
        button.textContent = "Sending..."

        try {
            const response = await fetch(this.inviteUrlValue, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                    "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
                },
                body: JSON.stringify({ name, email })
            })

            const data = await response.json()

            if (data.success) {
                this.setSelectedPerson(data.person_id, name, email)
            } else {
                alert(data.error || "Something went wrong. Please try again.")
                button.disabled = false
                button.textContent = originalText
            }
        } catch (error) {
            console.error("Invite error:", error)
            alert("Something went wrong. Please try again.")
            button.disabled = false
            button.textContent = originalText
        }
    }
}
