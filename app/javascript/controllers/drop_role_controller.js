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
        const assignableType = element.dataset.assignableType;
        const assignableId = element.dataset.assignableId;
        const sourceRoleId = element.dataset.sourceRoleId;

        // Store data for role-to-role dragging
        event.dataTransfer.effectAllowed = "move";
        event.dataTransfer.setData("assignableType", assignableType);
        event.dataTransfer.setData("assignableId", assignableId);
        event.dataTransfer.setData("sourceRoleId", sourceRoleId);
        // Backward compatibility
        event.dataTransfer.setData("personId", assignableId);

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
        let assignableType = event.dataTransfer.getData("assignableType");
        let assignableId = event.dataTransfer.getData("assignableId");
        let personId = event.dataTransfer.getData("personId");
        let sourceRoleId = event.dataTransfer.getData("sourceRoleId");

        // Fallback to text/plain for backward compatibility
        if (!assignableId && !personId) {
            personId = event.dataTransfer.getData("text/plain");
        }

        // Default to Person type if not specified
        if (!assignableType) {
            assignableType = "Person";
            assignableId = personId;
        }

        const showId = this.element.dataset.showId;
        const productionId = this.element.dataset.productionId;

        // If dragging from an assignment (role-to-role), sourceRoleId will be set
        if (sourceRoleId && sourceRoleId !== roleId) {
            // Remove from source role first, then add to target role
            this.moveAssignment(productionId, showId, assignableId, sourceRoleId, roleId, assignableType);
        } else {
            // Dragging from cast members list (cast-person drag)
            // First, remove anyone from the target role
            fetch(`/manage/productions/${productionId}/casting/shows/${showId}/remove_person_from_role`, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
                },
                body: JSON.stringify({ role_id: roleId })
            })
                .then(r => r.json())
                .then(data => {
                    // Get the entity who was removed from target role (if any)
                    const removedAssignableType = data.assignable_type;
                    const removedAssignableId = data.assignable_id;

                    // Ungray the entity who was removed from the target role
                    if (removedAssignableId && removedAssignableType) {
                        const targetType = removedAssignableType === "Person" ? "person" : "group";
                        const targetAttr = targetType === "person" ? "person-id" : "group-id";
                        const entityElement = document.querySelector(`[data-drag-cast-member-target="${targetType}"][data-${targetAttr}="${removedAssignableId}"]`);
                        if (entityElement) {
                            entityElement.classList.remove('opacity-50');
                        }
                    }

                    // Now assign the entity to the target role
                    const requestBody = { role_id: roleId };
                    if (assignableType === "Person") {
                        requestBody.person_id = assignableId;
                    } else if (assignableType === "Group") {
                        requestBody.group_id = assignableId;
                    }

                    return fetch(`/manage/productions/${productionId}/casting/shows/${showId}/assign_person_to_role`, {
                        method: "POST",
                        headers: {
                            "Content-Type": "application/json",
                            "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
                        },
                        body: JSON.stringify(requestBody)
                    });
                })
                .then(r => r.json())
                .then(data => {
                    // Find the entity element and add opacity-50
                    const targetType = assignableType === "Person" ? "person" : "group";
                    const entityElement = document.querySelector(`[data-drag-cast-member-target="${targetType}"][data-${targetType}-id="${assignableId}"]`);
                    if (entityElement) {
                        entityElement.classList.add('opacity-50');
                    }

                    // Update roles list
                    if (data.roles_html) {
                        document.getElementById("show-roles").outerHTML = data.roles_html;
                    }

                    // Update progress bar
                    this.updateProgressBar(data.progress);
                });
        }
    }

    moveAssignment(productionId, showId, assignableId, sourceRoleId, targetRoleId, assignableType) {
        // First, remove the entity from the source role
        fetch(`/manage/productions/${productionId}/casting/shows/${showId}/remove_person_from_role`, {
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
                return fetch(`/manage/productions/${productionId}/casting/shows/${showId}/remove_person_from_role`, {
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
                // Get the entity who was removed from target role (if any)
                const removedAssignableType = data.assignable_type;
                const removedAssignableId = data.assignable_id;

                // Ungray the entity who was removed from the target role
                if (removedAssignableId && removedAssignableType) {
                    const targetType = removedAssignableType === "Person" ? "person" : "group";
                    const targetAttr = targetType === "person" ? "person-id" : "group-id";
                    const entityElement = document.querySelector(`[data-drag-cast-member-target="${targetType}"][data-${targetAttr}="${removedAssignableId}"]`);
                    if (entityElement) {
                        entityElement.classList.remove('opacity-50');
                    }
                }

                // Now assign the entity to the target role
                const requestBody = { role_id: targetRoleId };
                if (assignableType === "Person") {
                    requestBody.person_id = assignableId;
                } else if (assignableType === "Group") {
                    requestBody.group_id = assignableId;
                } else {
                    // Fallback for backward compatibility
                    requestBody.person_id = assignableId;
                }

                return fetch(`/manage/productions/${productionId}/casting/shows/${showId}/assign_person_to_role`, {
                    method: "POST",
                    headers: {
                        "Content-Type": "application/json",
                        "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
                    },
                    body: JSON.stringify(requestBody)
                });
            })
            .then(r => r.json())
            .then(data => {
                // Update roles list
                if (data.roles_html) {
                    document.getElementById("show-roles").outerHTML = data.roles_html;
                }

                // Update progress bar
                this.updateProgressBar(data.progress);
            });
    }

    removeAssignment(event) {
        event.preventDefault();
        const assignmentId = event.currentTarget.dataset.assignmentId;
        const assignableType = event.currentTarget.dataset.assignableType;
        const assignableId = event.currentTarget.dataset.assignableId;
        const showId = this.element.dataset.showId;
        const productionId = this.element.dataset.productionId;

        fetch(`/manage/productions/${productionId}/casting/shows/${showId}/remove_person_from_role`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
            },
            body: JSON.stringify({ assignment_id: assignmentId })
        })
            .then(r => r.json())
            .then(data => {
                // Find the entity element and remove opacity-50
                if (assignableId) {
                    const targetType = assignableType === "Person" ? "person" : "group";
                    const targetAttr = targetType === "person" ? "person-id" : "group-id";
                    const entityElement = document.querySelector(`[data-drag-cast-member-target="${targetType}"][data-${targetAttr}="${assignableId}"]`);
                    if (entityElement) {
                        entityElement.classList.remove('opacity-50');
                    }
                }

                // Update roles list
                if (data.roles_html) {
                    document.getElementById("show-roles").outerHTML = data.roles_html;
                }

                // Update progress bar
                this.updateProgressBar(data.progress);
            });
    }

    updateProgressBar(progress) {
        if (!progress) return;

        const { assignment_count, role_count, percentage } = progress;

        // Update label
        const labelElement = document.getElementById('progress-label');
        if (labelElement) {
            if (percentage === 100) {
                labelElement.textContent = 'This show is 100% cast';
            } else {
                labelElement.textContent = `${assignment_count} of ${role_count} roles have been cast`;
            }
        }

        // Update fraction
        const fractionElement = document.getElementById('progress-fraction');
        if (fractionElement) {
            fractionElement.textContent = `${assignment_count}/${role_count} roles cast`;
            // Update color
            fractionElement.classList.remove('text-green-600', 'text-pink-600');
            fractionElement.classList.add(percentage === 100 ? 'text-green-600' : 'text-pink-600');
        }

        // Update progress bar
        const barElement = document.getElementById('progress-bar');
        if (barElement) {
            barElement.style.width = `${percentage}%`;
            // Update color
            barElement.classList.remove('bg-green-500', 'bg-pink-500');
            barElement.classList.add(percentage === 100 ? 'bg-green-500' : 'bg-pink-500');
        }
    }
}
