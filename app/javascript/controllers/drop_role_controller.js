import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["role", "person", "show", "assignment"];

    allowDrop(event) {
        event.preventDefault();
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
                if (data.cast_members_html) {
                    document.getElementById("show-cast-members").outerHTML = data.cast_members_html;
                }
                if (data.roles_html) {
                    document.getElementById("show-roles").outerHTML = data.roles_html;
                }
            });
    }

    removeAssignment(event) {
        event.preventDefault();
        const assignmentId = event.currentTarget.dataset.assignmentId;
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
                if (data.cast_members_html) {
                    document.getElementById("show-cast-members").outerHTML = data.cast_members_html;
                }
                if (data.roles_html) {
                    document.getElementById("show-roles").outerHTML = data.roles_html;
                }
            });
    }
}
