import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["searchController"]

    connect() {
        // Listen for custom open-modal event
        this.element.addEventListener('open-modal', (event) => {
            this.openWithDetails(event.detail);
        });
    }

    openWithDetails(details) {
        const { talentPoolId, talentPoolName } = details;

        // Update the modal title - now just "Add Person or Group to Talent Pool"
        const modalTitle = this.element.querySelector("#modal-title");
        if (modalTitle) {
            modalTitle.textContent = "Add Person or Group to Talent Pool";
        }

        // Set the talent pool ID in the search controller (still needed for excluding existing members)
        this.searchControllerTarget.setAttribute("data-people-search-talent-pool-id-value", talentPoolId);

        // Show the modal
        this.element.classList.remove("hidden");

        // Focus on the search input
        setTimeout(() => {
            const searchInput = this.element.querySelector('[data-people-search-target="input"]');
            if (searchInput) searchInput.focus();
        }, 100);
    }

    close() {
        // Hide the modal
        this.element.classList.add("hidden");

        // Clear the search input
        const searchInput = this.element.querySelector('[data-people-search-target="input"]');
        if (searchInput) {
            searchInput.value = "";
            this.element.querySelector('[data-people-search-target="results"]').innerHTML = "";
        }
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    addMember(event) {
        event.preventDefault();
        const button = event.currentTarget;
        const memberId = button.dataset.memberId;
        const memberType = button.dataset.memberType;
        const talentPoolId = button.dataset.talentPoolId;
        const productionId = this.element.dataset.productionId;

        if (!productionId) {
            console.error("Production ID not found");
            return;
        }

        // Determine endpoint and parameter based on member type
        // Routes are now collection routes (no talent pool id in URL)
        const endpoint = memberType === "Person" ? "add_person" : "add_group";
        const paramKey = memberType === "Person" ? "person_id" : "group_id";

        fetch(`/manage/productions/${productionId}/talent-pools/${endpoint}`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
            },
            body: JSON.stringify({ [paramKey]: memberId })
        })
            .then(r => r.text())
            .then(html => {
                // Replace the talent pool members list with the new HTML
                const talentPoolList = document.getElementById(`talent-pool-members-list-${talentPoolId}`);
                if (talentPoolList) {
                    talentPoolList.innerHTML = html;
                }

                // Remove the added member from the search results
                const resultItem = button.closest('.flex.items-center');
                if (resultItem) {
                    resultItem.remove();
                }

                // Close the modal
                this.close();
            });
    }
}
