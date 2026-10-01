import { Controller } from "@hotwired/stimulus"

// Ticketing settings → Door access → "Add someone else": search CocoScout
// people, choose one, then pick their level and submit.
export default class extends Controller {
    static targets = ["input", "results", "searchSection", "form", "personId", "selectedName", "selectedEmail"]
    static values = { url: String }

    disconnect() {
        clearTimeout(this.timer)
    }

    search() {
        clearTimeout(this.timer)
        this.timer = setTimeout(() => this.runSearch(), 250)
    }

    async runSearch() {
        const q = this.inputTarget.value.trim()
        try {
            const response = await fetch(`${this.urlValue}?q=${encodeURIComponent(q)}`, { headers: { Accept: "text/html" } })
            if (response.ok && q === this.inputTarget.value.trim()) this.resultsTarget.innerHTML = await response.text()
        } catch { /* the next keystroke tries again */ }
    }

    choose(event) {
        const { personId, personName, personEmail } = event.currentTarget.dataset
        this.personIdTarget.value = personId
        this.selectedNameTarget.textContent = personName
        this.selectedEmailTarget.textContent = personEmail || ""
        this.searchSectionTarget.classList.add("hidden")
        this.formTarget.classList.remove("hidden")
    }

    back() {
        this.personIdTarget.value = ""
        this.formTarget.classList.add("hidden")
        this.searchSectionTarget.classList.remove("hidden")
        this.inputTarget.focus()
    }
}
