import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["panel", "title", "searchController", "talentPoolsContainer"]

    open(event) {
        const button = event.currentTarget;
        const talentPoolId = button.dataset.talentPoolId;
        const talentPoolName = button.dataset.talentPoolName;

        // Update the panel title
        this.titleTarget.textContent = `Add to ${talentPoolName}`;

        // Set the talent pool ID in the search controller
        this.searchControllerTarget.setAttribute("data-people-search-talent-pool-id-value", talentPoolId);

        // Change the talent pools container to span 2 columns
        this.talentPoolsContainerTarget.classList.remove("lg:col-span-3");
        this.talentPoolsContainerTarget.classList.add("lg:col-span-2");

        // Hide all "Add member" buttons in the talent pools
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

        // Change the talent pools container back to full width
        this.talentPoolsContainerTarget.classList.remove("lg:col-span-2");
        this.talentPoolsContainerTarget.classList.add("lg:col-span-3");

        // Show all "Add member" buttons again
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

    addMember(event) {
        event.preventDefault();
        const button = event.currentTarget;
        const memberId = button.dataset.memberId;
        const memberType = button.dataset.memberType;
        const talentPoolId = button.dataset.talentPoolId;
        const productionId = document.querySelector('[data-controller="add-person-panel"]')?.dataset.productionId;

        if (!productionId) {
            console.error("Production ID not found");
            return;
        }

        // Determine endpoint and parameter based on member type
        const endpoint = memberType === "Person" ? "add_person" : "add_group";
        const paramKey = memberType === "Person" ? "person_id" : "group_id";

        fetch(`/manage/productions/${productionId}/talent-pools/${talentPoolId}/${endpoint}`, {
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

                    // Hide the newly added "Add member" button since the panel is still open
                    const newAddButton = talentPoolList.querySelector('[data-action="click->add-person-panel#open"]');
                    if (newAddButton) {
                        newAddButton.classList.add("hidden");
                    }
                }

                // Remove the added member from the search results
                const resultItem = button.closest('.flex.items-center');
                if (resultItem) {
                    resultItem.remove();
                }
            });
    }

    addPerson(event) {
        // Backward compatibility - redirect to addMember
        event.currentTarget.dataset.memberType = "Person";
        event.currentTarget.dataset.memberId = event.currentTarget.dataset.personId;
        this.addMember(event);
    }
}
