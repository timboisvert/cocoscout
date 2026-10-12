import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "searchInput", "searchResults", "searchSection",
        "selectedSection", "selectedName", "selectedEmail",
        "formSection", "emailField", "emailRow", "personIdField", "searchCancel"
    ]
    static values = { url: String }

    connect() {
        this.timeout = null
    }

    search() {
        clearTimeout(this.timeout)
        this.timeout = setTimeout(() => this.performSearch(), 250)
    }

    performSearch() {
        const query = this.searchInputTarget.value.trim()
        if (query.length < 2) {
            this.searchResultsTarget.innerHTML = '<p class="text-gray-500 text-sm p-4">Type at least 2 characters to search by name or email...</p>'
            return
        }
        fetch(`${this.urlValue}?q=${encodeURIComponent(query)}`)
            .then(r => r.text())
            .then(html => {
                this.searchResultsTarget.innerHTML = html
            })
    }

    selectPerson(event) {
        const { personName, personEmail, personId } = event.currentTarget.dataset

        this.searchSectionTarget.classList.add("hidden")
        this.searchCancelTarget.classList.add("hidden")
        this.selectedSectionTarget.classList.remove("hidden")
        this.formSectionTarget.classList.remove("hidden")

        // Someone outside the organization arrives without their email (the
        // search hides it); they're invited at the address on their account.
        this.selectedNameTarget.textContent = personName
        this.selectedEmailTarget.textContent = personEmail || "We'll email them at the address on their CocoScout account."
        this.emailFieldTarget.value = personEmail || ""
        this.personIdFieldTarget.value = personId
        this.toggleEmailRow(!!personEmail)
    }

    toggleEmailRow(show) {
        if (this.hasEmailRowTarget) this.emailRowTarget.classList.toggle("hidden", !show)
    }

    selectEmail(event) {
        const email = event.currentTarget.dataset.email

        this.searchSectionTarget.classList.add("hidden")
        this.searchCancelTarget.classList.add("hidden")
        this.selectedSectionTarget.classList.remove("hidden")
        this.formSectionTarget.classList.remove("hidden")

        this.selectedNameTarget.textContent = email
        this.selectedEmailTarget.textContent = "New invitation"
        this.emailFieldTarget.value = email
        this.personIdFieldTarget.value = ""
        this.toggleEmailRow(true)
    }

    backToSearch() {
        this.searchSectionTarget.classList.remove("hidden")
        this.searchCancelTarget.classList.remove("hidden")
        this.selectedSectionTarget.classList.add("hidden")
        this.formSectionTarget.classList.add("hidden")

        this.emailFieldTarget.value = ""
        this.personIdFieldTarget.value = ""
        this.toggleEmailRow(true)

        this.searchInputTarget.focus()
        this.searchInputTarget.select()
    }
}
