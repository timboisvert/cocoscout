import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["role", "person", "show", "assignment"];

    allowDrop(event) {
        event.preventDefault();
        // Add visual feedback when dragging over a role
        event.currentTarget.classList.add('ring-2', 'ring-pink-400', 'bg-pink-50');
    }

    dragLeave(event) {
        // Remove visual feedback when drag leaves the role
        event.currentTarget.classList.remove('ring-2', 'ring-pink-400', 'bg-pink-50');
    }

    dragStartAssignment(event) {
        const element = event.currentTarget;
        const personId = element.dataset.personId;
        const sourceRoleId = element.dataset.sourceRoleId;

        // Store data for role-to-role dragging
        event.dataTransfer.effectAllowed = "move";
        event.dataTransfer.setData("personId", personId);
        event.dataTransfer.setData("sourceRoleId", sourceRoleId);

        // Visual feedback
        element.style.opacity = "0.5";
    }

    dragEnd(event) {
        // Remove visual feedback
        event.currentTarget.style.opacity = "1";
    }

    assign(event) {
        event.preventDefault();
        event.currentTarget.classList.remove('ring-2', 'ring-pink-400', 'bg-pink-50');

        const roleId = event.currentTarget.dataset.roleId;
        let personId = event.dataTransfer.getData("personId");
        let sourceRoleId = event.dataTransfer.getData("sourceRoleId");

        // Fallback to text/plain for cast members dragged from other sources
        if (!personId) {
            personId = event.dataTransfer.getData("text/plain");
        }

        const showId = this.element.dataset.showId;
        const productionId = this.element.dataset.productionId;

        // If dragging from an assignment (role-to-role), sourceRoleId will be set
        if (sourceRoleId && sourceRoleId !== roleId) {
            // Remove from source role first, then add to target role
            this.moveAssignment(productionId, showId, personId, sourceRoleId, roleId);
        } else {
            // Dragging from cast members list (cast-person drag)
            // First, remove anyone from the target role
            fetch(`/manage/casting/productions/${productionId}/shows/${showId}/remove_person_from_role`, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
                },
                body: JSON.stringify({ role_id: roleId })
            })
                .then(r => r.json())
                .then(data => {
                    // Get the person who was removed from target role (if any)
                    const removedPersonId = data.person_id;

                    // Ungray the person who was removed from the target role
                    if (removedPersonId) {
                        const personElement = document.querySelector(`[data-drag-cast-member-target="person"][data-person-id="${removedPersonId}"]`);
                        if (personElement) {
                            personElement.classList.remove('opacity-50');
                        }
                    }

                    // Now assign the person to the target role
                    return fetch(`/manage/casting/productions/${productionId}/shows/${showId}/assign_person_to_role`, {
                        method: "POST",
                        headers: {
                            "Content-Type": "application/json",
                            "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
                        },
                        body: JSON.stringify({ person_id: personId, role_id: roleId })
                    });
                })
                .then(r => r.json())
                .then(data => {
                    // Find the person element and add opacity-50
                    const personElement = document.querySelector(`[data-drag-cast-member-target="person"][data-person-id="${personId}"]`);
                    if (personElement) {
                        personElement.classList.add('opacity-50');
                    }

                    // Update roles list
                    if (data.roles_html) {
                        document.getElementById("show-roles").outerHTML = data.roles_html;
                    }
                });
        }
    }

    moveAssignment(productionId, showId, personId, sourceRoleId, targetRoleId) {
        // First, remove the person from the source role
        fetch(`/manage/casting/productions/${productionId}/shows/${showId}/remove_person_from_role`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
            },
            body: JSON.stringify({ role_id: sourceRoleId })
        })
            .then(r => r.json())
            .then(data => {
                // Now check if target role has an assignment and remove it
                return fetch(`/manage/casting/productions/${productionId}/shows/${showId}/remove_person_from_role`, {
                    method: "POST",
                    headers: {
                        "Content-Type": "application/json",
                        "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
                    },
                    body: JSON.stringify({ role_id: targetRoleId })
                });
            })
            .then(r => r.json())
            .then(data => {
                // Get the person who was removed from target role (if any)
                const removedPersonId = data.person_id;

                // Ungray the person who was removed from the target role
                if (removedPersonId) {
                    const personElement = document.querySelector(`[data-drag-cast-member-target="person"][data-person-id="${removedPersonId}"]`);
                    if (personElement) {
                        personElement.classList.remove('opacity-50');
                    }
                }

                // Now assign the person to the target role
                return fetch(`/manage/casting/productions/${productionId}/shows/${showId}/assign_person_to_role`, {
                    method: "POST",
                    headers: {
                        "Content-Type": "application/json",
                        "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
                    },
                    body: JSON.stringify({ person_id: personId, role_id: targetRoleId })
                });
            })
            .then(r => r.json())
            .then(data => {
                // Update roles list
                if (data.roles_html) {
                    document.getElementById("show-roles").outerHTML = data.roles_html;
                }
            });
    }

    removeAssignment(event) {
        event.preventDefault();
        const assignmentId = event.currentTarget.dataset.assignmentId;
        const personId = event.currentTarget.dataset.personId;
        const showId = this.element.dataset.showId;
        const productionId = this.element.dataset.productionId;

        fetch(`/manage/casting/productions/${productionId}/shows/${showId}/remove_person_from_role`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
            },
            body: JSON.stringify({ assignment_id: assignmentId })
        })
            .then(r => r.json())
            .then(data => {
                // Find the person element and remove opacity-50
                if (personId) {
                    const personElement = document.querySelector(`[data-drag-cast-member-target="person"][data-person-id="${personId}"]`);
                    if (personElement) {
                        personElement.classList.remove('opacity-50');
                    }
                }

                // Update roles list
                if (data.roles_html) {
                    document.getElementById("show-roles").outerHTML = data.roles_html;
                }
            });
    }
}
