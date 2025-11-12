import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = { productionId: Number, castId: Number }

    add(event) {
        event.preventDefault();
        const button = event.currentTarget;
        const personId = button.dataset.personId;

        // Try to get cast ID from button data attribute first (for search results),
        // then fall back to controller value
        let castId = button.dataset.castIdValue;
        if (!castId) {
            castId = this.castIdValue;
        }

        const productionId = this.productionIdValue;

        fetch(`/manage/productions/${productionId}/casts/${castId}/add_person`, {
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
                // Replace the cast members list with the new HTML
                const castList = document.getElementById(`cast-members-list-${castId}`);
                if (castList) castList.innerHTML = html;
            });
    }

    remove(event) {
        event.preventDefault();

        if (!confirm("Are you sure you want to remove this person from the cast?")) {
            return;
        }

        const personId = event.currentTarget.dataset.personId;
        const productionId = this.productionIdValue;
        const castId = this.castIdValue;
        fetch(`/manage/productions/${productionId}/casts/${castId}/remove_person`, {
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
                // Replace the cast members list with the new HTML
                const castList = document.getElementById(`cast-members-list-${castId}`);
                if (castList) castList.innerHTML = html;

                // If the add-person panel is open, hide the newly rendered "Add a person" button
                const panel = document.getElementById("add-person-panel");
                if (panel && !panel.classList.contains("hidden")) {
                    const newAddButton = castList.querySelector('[data-action="click->add-person-panel#open"]');
                    if (newAddButton) {
                        newAddButton.classList.add("hidden");
                    }
                }
            });
    }

    dragStart(event) {
        const element = event.currentTarget;
        const personId = element.dataset.personId;
        const sourceCastId = element.dataset.sourceCastId;

        // Store data in the drag event
        event.dataTransfer.effectAllowed = "move";
        event.dataTransfer.setData("personId", personId);
        event.dataTransfer.setData("sourceCastId", sourceCastId);

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
        const sourceCastId = event.dataTransfer.getData("sourceCastId");
        const targetCastId = dropZone.dataset.castId;

        // Don't do anything if dropping on the same cast
        if (sourceCastId === targetCastId) {
            return;
        }

        // Get production ID from the nearest element that has it
        const gridElement = document.querySelector('[data-controller="add-person-panel"]');
        const productionId = gridElement?.dataset.productionId;

        if (!productionId) {
            console.error("Production ID not found");
            return;
        }

        // Remove from source cast and add to target cast
        this.movePerson(productionId, personId, sourceCastId, targetCastId);
    }

    movePerson(productionId, personId, sourceCastId, targetCastId) {
        // First remove from source cast
        fetch(`/manage/productions/${productionId}/casts/${sourceCastId}/remove_person`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
            },
            body: JSON.stringify({ person_id: personId })
        })
            .then(r => r.text())
            .then(html => {
                // Update source cast list
                const sourceCastList = document.getElementById(`cast-members-list-${sourceCastId}`);
                if (sourceCastList) sourceCastList.innerHTML = html;

                // Then add to target cast
                return fetch(`/manage/productions/${productionId}/casts/${targetCastId}/add_person`, {
                    method: "POST",
                    headers: {
                        "Content-Type": "application/json",
                        "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
                    },
                    body: JSON.stringify({ person_id: personId })
                });
            })
            .then(r => r.text())
            .then(html => {
                // Update target cast list
                const targetCastList = document.getElementById(`cast-members-list-${targetCastId}`);
                if (targetCastList) targetCastList.innerHTML = html;
            });
    }

}
