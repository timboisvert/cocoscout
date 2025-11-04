import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["panel", "title", "searchController", "castsContainer"]

    open(event) {
        const button = event.currentTarget;
        const castId = button.dataset.castId;
        const castName = button.dataset.castName;

        // Update the panel title
        this.titleTarget.textContent = `Add Person to ${castName}`;

        // Set the cast ID in the search controller
        this.searchControllerTarget.setAttribute("data-people-search-cast-id-value", castId);

        // Change the casts container to span 2 columns
        this.castsContainerTarget.classList.remove("lg:col-span-3");
        this.castsContainerTarget.classList.add("lg:col-span-2");

        // Hide all "Add a person" buttons in the casts
        document.querySelectorAll('[data-action="click->add-person-panel#open"]').forEach(btn => {
            btn.classList.add("hidden");
        });

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

        // Change the casts container back to full width
        this.castsContainerTarget.classList.remove("lg:col-span-2");
        this.castsContainerTarget.classList.add("lg:col-span-3");

        // Show all "Add a person" buttons again
        document.querySelectorAll('[data-action="click->add-person-panel#open"]').forEach(btn => {
            btn.classList.remove("hidden");
        });

        // Clear the search input
        const searchInput = this.panelTarget.querySelector('[data-people-search-target="input"]');
        if (searchInput) {
            searchInput.value = "";
            this.panelTarget.querySelector('[data-people-search-target="results"]').innerHTML = "";
        }
    }

    addPerson(event) {
        event.preventDefault();
        const button = event.currentTarget;
        const personId = button.dataset.personId;
        const castId = button.dataset.castId;
        const productionId = document.querySelector('[data-controller="add-person-panel"]')?.dataset.productionId;

        if (!productionId) {
            console.error("Production ID not found");
            return;
        }

        fetch(`/manage/productions/${productionId}/casts/${castId}/add_person`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
            },
            body: JSON.stringify({ person_id: personId })
        })
            .then(r => r.text())
            .then(html => {
                // Replace the cast members list with the new HTML
                const castList = document.getElementById(`cast-members-list-${castId}`);
                if (castList) castList.innerHTML = html;

                // Hide the newly added "Add a person" button since the panel is still open
                const newAddButton = castList.querySelector('[data-action="click->add-person-panel#open"]');
                if (newAddButton) {
                    newAddButton.classList.add("hidden");
                }

                // Remove the added person from the search results
                const resultItem = button.closest('.flex.items-center');
                if (resultItem) {
                    resultItem.remove();
                }
            });
    }
}
