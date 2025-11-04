import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["panel", "title", "searchController"]

    open(event) {
        const button = event.currentTarget;
        const castId = button.dataset.castId;
        const castName = button.dataset.castName;

        // Update the panel title
        this.titleTarget.textContent = `Add Person to ${castName}`;

        // Set the cast ID in the search controller
        this.searchControllerTarget.setAttribute("data-people-search-cast-id-value", castId);

        // Show the panel
        this.panelTarget.classList.remove("hidden");

        // Focus on the search input
        setTimeout(() => {
            const searchInput = this.panelTarget.querySelector('[data-people-search-target="input"]');
            if (searchInput) searchInput.focus();
        }, 0);
    }

    close() {
        // Hide the panel
        this.panelTarget.classList.add("hidden");

        // Clear the search input
        const searchInput = this.panelTarget.querySelector('[data-people-search-target="input"]');
        if (searchInput) {
            searchInput.value = "";
            this.panelTarget.querySelector('[data-people-search-target="results"]').innerHTML = "";
        }
    }
}
