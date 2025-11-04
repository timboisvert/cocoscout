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

    assign(event) {
        event.preventDefault();
        const roleId = event.currentTarget.dataset.roleId;
        const personId = event.dataTransfer.getData("text/plain");
        const showId = this.element.dataset.showId;

        fetch(`/manage/shows/${showId}/assign_person_to_role`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
            },
            body: JSON.stringify({ person_id: personId, role_id: roleId })
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

    removeAssignment(event) {
        event.preventDefault();
        const assignmentId = event.currentTarget.dataset.assignmentId;
        const personId = event.currentTarget.dataset.personId;
        const showId = this.element.dataset.showId;

        fetch(`/manage/shows/${showId}/remove_person_from_role`, {
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
