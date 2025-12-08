import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = { productionId: Number, talentPoolId: Number }

    add(event) {
        event.preventDefault();
        const button = event.currentTarget;
        const personId = button.dataset.personId;

        // Try to get talent pool ID from button data attribute first (for search results),
        // then fall back to controller value
        let talentPoolId = button.dataset.talentPoolIdValue;
        if (!talentPoolId) {
            talentPoolId = this.talentPoolIdValue;
        }

        const productionId = this.productionIdValue;

        fetch(`/manage/productions/${productionId}/casting/talent-pools/${talentPoolId}/add_person`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content,
                "X-Requested-With": "XMLHttpRequest"
            },
            body: JSON.stringify({ person_id: personId })
        })
            .then(r => r.text())
            .then(html => {
                // Replace the talent pool members list with the new HTML
                const poolList = document.getElementById(`talent-pool-members-list-${talentPoolId}`);
                if (poolList) poolList.innerHTML = html;
            });
    }

    remove(event) {
        event.preventDefault();

        const memberType = event.currentTarget.dataset.memberType;
        const personId = event.currentTarget.dataset.personId;
        const productionId = this.productionIdValue;
        const talentPoolId = this.talentPoolIdValue;

        // Navigate to confirmation page
        const endpoint = memberType === "Person" ? "confirm-remove-person" : "confirm-remove-group";
        window.location.href = `/manage/productions/${productionId}/talent-pools/${talentPoolId}/${endpoint}/${personId}`;
    }

    dragStart(event) {
        const element = event.currentTarget;
        const personId = element.dataset.personId;
        const memberType = element.dataset.memberType;
        const sourceTalentPoolId = element.dataset.sourceTalentPoolId;

        // Store data in the drag event
        event.dataTransfer.effectAllowed = "move";
        event.dataTransfer.setData("personId", personId);
        event.dataTransfer.setData("memberType", memberType);
        event.dataTransfer.setData("sourceTalentPoolId", sourceTalentPoolId);

        // Add visual feedback
        element.style.opacity = "0.5";

        // Hide the Remove button
        const removeButton = element.querySelector('[data-remove-button]');
        if (removeButton) {
            removeButton.classList.add("hidden");
        }
    }

    dragEnd(event) {
        const element = event.currentTarget;
        // Remove visual feedback
        element.style.opacity = "1";

        // Show the Remove button again
        const removeButton = element.querySelector('[data-remove-button]');
        if (removeButton) {
            removeButton.classList.remove("hidden");
        }
    }

    // These methods are on the drop zone (cast members list)
    dragOver(event) {
        event.preventDefault();
        event.dataTransfer.dropEffect = "move";
        const dropZone = event.currentTarget;
        dropZone.classList.add("ring-2", "ring-pink-400", "bg-pink-50");
    }

    dragLeave(event) {
        const dropZone = event.currentTarget;
        dropZone.classList.remove("ring-2", "ring-pink-400", "bg-pink-50");
    }

    drop(event) {
        event.preventDefault();
        event.stopPropagation();

        const dropZone = event.currentTarget;
        dropZone.classList.remove("ring-2", "ring-pink-400", "bg-pink-50");

        const personId = event.dataTransfer.getData("personId");
        const memberType = event.dataTransfer.getData("memberType") || "Person";
        const sourceTalentPoolId = event.dataTransfer.getData("sourceTalentPoolId");
        const targetTalentPoolId = dropZone.dataset.talentPoolId;

        // Don't do anything if dropping on the same talent pool
        if (sourceTalentPoolId === targetTalentPoolId) {
            return;
        }

        // Get production ID from the modal or page
        const modal = document.getElementById('add-member-modal');
        const productionId = modal?.dataset.productionId || this.productionIdValue;

        if (!productionId) {
            console.error("Production ID not found");
            return;
        }

        // Remove from source pool and add to target pool
        this.moveMember(productionId, personId, memberType, sourceTalentPoolId, targetTalentPoolId);
    }

    moveMember(productionId, memberId, memberType, sourceTalentPoolId, targetTalentPoolId) {
        // Determine endpoints based on member type
        const removeEndpoint = memberType === "Person" ? "remove_person" : "remove_group";
        const addEndpoint = memberType === "Person" ? "add_person" : "add_group";
        const paramKey = memberType === "Person" ? "person_id" : "group_id";

        // First remove from source pool
        fetch(`/manage/productions/${productionId}/talent-pools/${sourceTalentPoolId}/${removeEndpoint}`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content,
                "X-Requested-With": "XMLHttpRequest"
            },
            body: JSON.stringify({ [paramKey]: memberId })
        })
            .then(r => r.text())
            .then(html => {
                // Update source pool list
                const sourcePoolList = document.getElementById(`talent-pool-members-list-${sourceTalentPoolId}`);
                if (sourcePoolList) sourcePoolList.innerHTML = html;

                // Then add to target pool
                return fetch(`/manage/productions/${productionId}/talent-pools/${targetTalentPoolId}/${addEndpoint}`, {
                    method: "POST",
                    headers: {
                        "Content-Type": "application/json",
                        "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content,
                        "X-Requested-With": "XMLHttpRequest"
                    },
                    body: JSON.stringify({ [paramKey]: memberId })
                });
            })
            .then(r => r.text())
            .then(html => {
                // Update target pool list
                const targetPoolList = document.getElementById(`talent-pool-members-list-${targetTalentPoolId}`);
                if (targetPoolList) targetPoolList.innerHTML = html;
            });
    }

}
