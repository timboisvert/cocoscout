import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "input", "results", "searchSection",
        "selectedUser", "selectedUserName", "selectedUserEmail",
        "userIdInput", "emailInput",
        "roleSection", "inviteSection"
    ]
    static values = { url: String, formUrl: String }

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

    selectUser(event) {
        const userId = event.currentTarget.dataset.userId
        const userName = event.currentTarget.dataset.userName
        const userEmail = event.currentTarget.dataset.userEmail

        // Hide search, show selected user + role selection
        this.searchSectionTarget.classList.add("hidden")
        this.selectedUserTarget.classList.remove("hidden")
        this.roleSectionTarget.classList.remove("hidden")

        // Set display info
        this.selectedUserNameTarget.textContent = userName
        this.selectedUserEmailTarget.textContent = userEmail

        // Set hidden form field
        this.userIdInputTarget.value = userId
        this.emailInputTarget.value = ""
    }

    showInviteForm(event) {
        const email = event.currentTarget.dataset.email || ""

        // Hide search, show invite form + role selection
        this.searchSectionTarget.classList.add("hidden")
        this.inviteSectionTarget.classList.remove("hidden")
        this.roleSectionTarget.classList.remove("hidden")

        // Set the email
        this.emailInputTarget.value = email
        this.userIdInputTarget.value = ""
    }

    backToSearch() {
        // Show search, hide everything else
        this.searchSectionTarget.classList.remove("hidden")
        this.selectedUserTarget.classList.add("hidden")
        this.roleSectionTarget.classList.add("hidden")
        this.inviteSectionTarget.classList.add("hidden")

        // Clear hidden fields
        this.userIdInputTarget.value = ""
        this.emailInputTarget.value = ""

        // Focus search input
        this.inputTarget.focus()
    }

    reset() {
        this.inputTarget.value = ""
        this.resultsTarget.innerHTML = ""
        this.userIdInputTarget.value = ""
        this.emailInputTarget.value = ""
        this.searchSectionTarget.classList.remove("hidden")
        this.selectedUserTarget.classList.add("hidden")
        this.roleSectionTarget.classList.add("hidden")
        this.inviteSectionTarget.classList.add("hidden")
    }
}
