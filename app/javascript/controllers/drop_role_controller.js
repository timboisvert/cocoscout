import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["role", "person", "show", "assignment"];

    allowDrop(event) {
        event.preventDefault();

        // Check if this is a restricted role
        const roleElement = event.currentTarget;
        const isRestricted = roleElement.dataset.roleRestricted === "true";

        if (isRestricted) {
            // For restricted roles, show a different visual indicator
            // We can't check eligibility here because dataTransfer data isn't available in dragover
            // The actual validation happens in assign()
            roleElement.classList.add('ring-2', 'ring-amber-400', 'bg-amber-50');
        } else {
            // Add visual feedback when dragging over a role
            roleElement.classList.add('ring-2', 'ring-pink-400', 'bg-pink-50');
        }
    }

    dragLeave(event) {
        // Remove visual feedback when drag leaves the role
        event.currentTarget.classList.remove('ring-2', 'ring-pink-400', 'bg-pink-50', 'ring-amber-400', 'bg-amber-50');
    }

    isEligibleForRole(roleElement, assignableType, assignableId) {
        const isRestricted = roleElement.dataset.roleRestricted === "true";

        // If role is not restricted, anyone can be assigned
        if (!isRestricted) return true;

        // Groups are not supported for restricted roles (only people)
        if (assignableType === "Group") return false;

        // Check if the person is in the eligible list
        const eligiblePersonIds = JSON.parse(roleElement.dataset.eligiblePersonIds || "[]");
        return eligiblePersonIds.includes(parseInt(assignableId));
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
        event.dataTransfer.setData("sourceRoleId", sourceRoleId || "");
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
        const roleElement = event.currentTarget;
        roleElement.classList.remove('ring-2', 'ring-pink-400', 'bg-pink-50', 'ring-amber-400', 'bg-amber-50');

        // All roles now use role-id (both production and show-specific roles)
        const roleId = roleElement.dataset.roleId;
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

        // Check eligibility for restricted roles
        if (!this.isEligibleForRole(roleElement, assignableType, assignableId)) {
            // Show a brief visual indicator that the drop was rejected
            roleElement.classList.add('ring-2', 'ring-red-400', 'bg-red-50');
            setTimeout(() => {
                roleElement.classList.remove('ring-2', 'ring-red-400', 'bg-red-50');
            }, 500);
            return;
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
            const removeBody = { role_id: roleId };

            fetch(`/manage/productions/${productionId}/casting/shows/${showId}/remove_person_from_role`, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
                },
                body: JSON.stringify(removeBody)
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

                    // Update progress bar and finalize section
                    this.updateProgressBar(data.progress);
                    if (data.finalize_section_html) {
                        this.updateFinalizeSection(data.finalize_section_html);
                    }
                });
        }
    }

    // Handle click-to-assign for restricted roles
    assignFromClick(event) {
        event.preventDefault();
        const button = event.currentTarget;
        const roleId = button.dataset.roleId;
        const assignableType = button.dataset.assignableType;
        const assignableId = button.dataset.assignableId;
        const showId = this.element.dataset.showId;
        const productionId = this.element.dataset.productionId;

        const requestBody = { role_id: roleId };
        if (assignableType === "Person") {
            requestBody.person_id = assignableId;
        } else if (assignableType === "Group") {
            requestBody.group_id = assignableId;
        }

        fetch(`/manage/productions/${productionId}/casting/shows/${showId}/assign_person_to_role`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
            },
            body: JSON.stringify(requestBody)
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

                // Update progress bar and finalize section
                this.updateProgressBar(data.progress);
                if (data.finalize_section_html) {
                    this.updateFinalizeSection(data.finalize_section_html);
                }
            });
    }

    moveAssignment(productionId, showId, assignableId, sourceRoleId, targetRoleId, assignableType) {
        // All roles now use role_id
        const sourceRemoveBody = { role_id: sourceRoleId };
        const targetRemoveBody = { role_id: targetRoleId };

        // First, remove the entity from the source role
        fetch(`/manage/productions/${productionId}/casting/shows/${showId}/remove_person_from_role`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
            },
            body: JSON.stringify(sourceRemoveBody)
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
                    body: JSON.stringify(targetRemoveBody)
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

                // Update progress bar and finalize section
                this.updateProgressBar(data.progress);
                if (data.finalize_section_html) {
                    this.updateFinalizeSection(data.finalize_section_html);
                }
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

                // Update progress bar and finalize section
                this.updateProgressBar(data.progress);
                if (data.finalize_section_html) {
                    this.updateFinalizeSection(data.finalize_section_html);
                }
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

        // Show/hide finalize section based on whether fully cast
        const finalizeSection = document.getElementById('finalize-section-wrapper');
        if (finalizeSection) {
            if (percentage === 100) {
                finalizeSection.classList.remove('hidden');
            } else {
                finalizeSection.classList.add('hidden');
            }
        }
    }

    // Update the finalize section with fresh HTML from the server
    updateFinalizeSection(finalizeSectionHtml) {
        const finalizeWrapper = document.getElementById('finalize-section-wrapper');
        if (finalizeWrapper && finalizeSectionHtml) {
            finalizeWrapper.innerHTML = finalizeSectionHtml;
        }
    }

    // Create a vacancy from an existing assignment
    createVacancy(event) {
        event.preventDefault();
        const button = event.currentTarget;
        const roleId = button.dataset.roleId;
        const showId = this.element.dataset.showId;
        const productionId = this.element.dataset.productionId;

        // Optional: prompt for reason
        const reason = prompt("Reason for vacancy (optional):");
        if (reason === null) return; // User cancelled

        fetch(`/manage/productions/${productionId}/casting/shows/${showId}/create_vacancy`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
            },
            body: JSON.stringify({ role_id: roleId, reason: reason || null })
        })
            .then(r => r.json())
            .then(data => {
                if (data.error) {
                    alert(data.error);
                    return;
                }

                // Update roles list
                if (data.roles_html) {
                    document.getElementById("show-roles").outerHTML = data.roles_html;
                }

                // Update cast members list
                if (data.cast_members_html) {
                    const castMembersList = document.getElementById("cast-members-list");
                    if (castMembersList) {
                        castMembersList.outerHTML = data.cast_members_html;
                    }
                }

                // Update progress bar and finalize section
                this.updateProgressBar(data.progress);
                if (data.finalize_section_html) {
                    this.updateFinalizeSection(data.finalize_section_html);
                }
            });
    }
}
