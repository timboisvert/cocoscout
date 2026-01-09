import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "role", "person", "show", "assignment", "assignModal", "rolesContainer",
        // Add Person modal targets
        "addPersonModal", "addPersonRoleName", "addPersonRoleId", "addPersonSlotPosition",
        "addPersonSearchTab", "addPersonGuestTab",
        "personSearchInput", "personSearchSpinner", "personSearchResults",
        "addPersonGuestName", "addPersonGuestEmail"
    ];
    static values = { showId: String, productionId: String, castingSource: String, clickToAdd: Boolean };

    connect() {
        // Close modal on escape key
        this.handleEscape = (event) => {
            if (event.key === 'Escape') {
                this.closeAssignModal();
                this.closeAddPersonModal();
            }
        };
        document.addEventListener('keydown', this.handleEscape);

        // Debounce timer for search
        this.searchTimeout = null;
    }

    disconnect() {
        document.removeEventListener('keydown', this.handleEscape);
    }

    // Helper to get showId - from value or from rolesContainer
    get showId() {
        if (this.hasShowIdValue) return this.showIdValue;
        if (this.hasRolesContainerTarget) return this.rolesContainerTarget.dataset.showId;
        return this.element.dataset.showId;
    }

    // Helper to get productionId - from value or from rolesContainer
    get productionId() {
        if (this.hasProductionIdValue) return this.productionIdValue;
        if (this.hasRolesContainerTarget) return this.rolesContainerTarget.dataset.productionId;
        return this.element.dataset.productionId;
    }

    // Open the assign modal for mobile
    openAssignModal(event) {
        event.preventDefault();
        const button = event.currentTarget;
        const roleId = button.dataset.roleId;
        const roleName = button.dataset.roleName;

        // Store the role we're assigning to
        this.currentAssignRoleId = roleId;

        // Update modal title
        const modal = this.assignModalTarget;
        const titleEl = modal.querySelector('[data-modal-title]');
        if (titleEl) {
            titleEl.textContent = `Assign to ${roleName}`;
        }

        // Show the modal
        modal.classList.remove('hidden');
        document.body.classList.add('overflow-hidden');
    }

    closeAssignModal() {
        const modal = this.assignModalTarget;
        if (modal) {
            modal.classList.add('hidden');
            document.body.classList.remove('overflow-hidden');
        }
        this.currentAssignRoleId = null;
    }

    // Open the add guest modal
    openGuestModal(event) {
        event.preventDefault();
        const modal = document.getElementById('add-guest-modal');
        if (modal) {
            modal.classList.remove('hidden');
            document.body.classList.add('overflow-hidden');
            // Focus on name input
            setTimeout(() => {
                document.getElementById('guest-name-input')?.focus();
            }, 100);
        }
    }

    // Close the add guest modal
    closeGuestModal() {
        const modal = document.getElementById('add-guest-modal');
        if (modal) {
            modal.classList.add('hidden');
            document.body.classList.remove('overflow-hidden');
            // Clear inputs
            const nameInput = document.getElementById('guest-name-input');
            const emailInput = document.getElementById('guest-email-input');
            const roleSelect = document.getElementById('guest-role-select');
            if (nameInput) nameInput.value = '';
            if (emailInput) emailInput.value = '';
            if (roleSelect) roleSelect.value = '';
        }
    }

    // ========================================
    // Add Person Modal (Manual Entry / Hybrid)
    // ========================================

    // Open the add person modal when clicking on an empty slot
    openAddPersonModal(event) {
        event.preventDefault();
        event.stopPropagation();

        const button = event.currentTarget;
        const roleId = button.dataset.roleId;
        const roleName = button.dataset.roleName;
        const slotPosition = button.dataset.slotPosition;

        if (!this.hasAddPersonModalTarget) return;

        // Store role info
        if (this.hasAddPersonRoleIdTarget) {
            this.addPersonRoleIdTarget.value = roleId;
        }
        if (this.hasAddPersonSlotPositionTarget) {
            this.addPersonSlotPositionTarget.value = slotPosition;
        }
        if (this.hasAddPersonRoleNameTarget) {
            this.addPersonRoleNameTarget.textContent = roleName;
        }

        // Reset to search tab
        this.switchToSearchTab();

        // Clear previous search
        if (this.hasPersonSearchInputTarget) {
            this.personSearchInputTarget.value = '';
        }
        if (this.hasPersonSearchResultsTarget) {
            this.personSearchResultsTarget.innerHTML = '<p class="text-sm text-gray-400 text-center py-4">Type to search...</p>';
        }

        // Clear guest inputs
        if (this.hasAddPersonGuestNameTarget) {
            this.addPersonGuestNameTarget.value = '';
        }
        if (this.hasAddPersonGuestEmailTarget) {
            this.addPersonGuestEmailTarget.value = '';
        }

        // Show modal
        this.addPersonModalTarget.classList.remove('hidden');
        document.body.classList.add('overflow-hidden');

        // Focus on search input
        setTimeout(() => {
            this.personSearchInputTarget?.focus();
        }, 100);
    }

    // Close the add person modal
    closeAddPersonModal() {
        if (!this.hasAddPersonModalTarget) return;

        this.addPersonModalTarget.classList.add('hidden');
        document.body.classList.remove('overflow-hidden');
    }

    // Switch between search and guest tabs
    switchAddPersonTab(event) {
        const tab = event.currentTarget.dataset.tab;
        if (tab === 'search') {
            this.switchToSearchTab();
        } else if (tab === 'guest') {
            this.switchToGuestTab();
        }
    }

    switchToSearchTab() {
        if (!this.hasAddPersonSearchTabTarget || !this.hasAddPersonGuestTabTarget) return;

        // Update tab styles
        const tabs = this.element.querySelectorAll('.add-person-tab');
        tabs.forEach(t => {
            if (t.dataset.tab === 'search') {
                t.classList.add('border-pink-500', 'text-pink-600');
                t.classList.remove('border-transparent', 'text-gray-500');
            } else {
                t.classList.remove('border-pink-500', 'text-pink-600');
                t.classList.add('border-transparent', 'text-gray-500');
            }
        });

        // Show search tab, hide guest tab
        this.addPersonSearchTabTarget.classList.remove('hidden');
        this.addPersonGuestTabTarget.classList.add('hidden');
    }

    switchToGuestTab() {
        if (!this.hasAddPersonSearchTabTarget || !this.hasAddPersonGuestTabTarget) return;

        // Update tab styles
        const tabs = this.element.querySelectorAll('.add-person-tab');
        tabs.forEach(t => {
            if (t.dataset.tab === 'guest') {
                t.classList.add('border-pink-500', 'text-pink-600');
                t.classList.remove('border-transparent', 'text-gray-500');
            } else {
                t.classList.remove('border-pink-500', 'text-pink-600');
                t.classList.add('border-transparent', 'text-gray-500');
            }
        });

        // Show guest tab, hide search tab
        this.addPersonGuestTabTarget.classList.remove('hidden');
        this.addPersonSearchTabTarget.classList.add('hidden');

        // Focus on name input
        setTimeout(() => {
            this.addPersonGuestNameTarget?.focus();
        }, 100);
    }

    // Search for people in the organization
    searchPeople() {
        if (!this.hasPersonSearchInputTarget) return;

        const query = this.personSearchInputTarget.value.trim();

        // Clear existing timeout
        if (this.searchTimeout) {
            clearTimeout(this.searchTimeout);
        }

        // Need at least 2 characters
        if (query.length < 2) {
            if (this.hasPersonSearchResultsTarget) {
                this.personSearchResultsTarget.innerHTML = '<p class="text-sm text-gray-400 text-center py-4">Type at least 2 characters...</p>';
            }
            return;
        }

        // Show spinner
        if (this.hasPersonSearchSpinnerTarget) {
            this.personSearchSpinnerTarget.classList.remove('hidden');
        }

        // Debounce the search
        this.searchTimeout = setTimeout(() => {
            this.performSearch(query);
        }, 250);
    }

    async performSearch(query) {
        const productionId = this.productionId;

        try {
            const response = await fetch(`/manage/productions/${productionId}/casting/search_people?q=${encodeURIComponent(query)}`, {
                headers: {
                    "Accept": "application/json",
                    "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
                }
            });

            const data = await response.json();

            // Hide spinner
            if (this.hasPersonSearchSpinnerTarget) {
                this.personSearchSpinnerTarget.classList.add('hidden');
            }

            // Render results
            this.renderSearchResults(data.people || [], data.groups || []);

        } catch (error) {
            console.error('Error searching people:', error);
            if (this.hasPersonSearchSpinnerTarget) {
                this.personSearchSpinnerTarget.classList.add('hidden');
            }
            if (this.hasPersonSearchResultsTarget) {
                this.personSearchResultsTarget.innerHTML = '<p class="text-sm text-red-500 text-center py-4">Error searching. Please try again.</p>';
            }
        }
    }

    renderSearchResults(people, groups) {
        if (!this.hasPersonSearchResultsTarget) return;

        if (people.length === 0 && groups.length === 0) {
            this.personSearchResultsTarget.innerHTML = '<p class="text-sm text-gray-400 text-center py-4">No results found</p>';
            return;
        }

        let html = '';

        people.forEach(person => {
            html += this.renderPersonResult(person);
        });

        groups.forEach(group => {
            html += this.renderGroupResult(group);
        });

        this.personSearchResultsTarget.innerHTML = html;
    }

    renderPersonResult(person) {
        const headshot = person.headshot_url
            ? `<img src="${person.headshot_url}" alt="${person.name}" class="w-10 h-10 rounded-lg object-cover flex-shrink-0">`
            : `<div class="w-10 h-10 rounded-lg bg-gray-200 flex items-center justify-center text-gray-700 font-bold text-xs flex-shrink-0">${person.initials || ''}</div>`;

        return `
            <button type="button"
                class="w-full flex items-center gap-3 p-3 rounded-lg hover:bg-pink-50 transition-all cursor-pointer text-left"
                data-action="click->drop-role#selectPersonFromSearch"
                data-person-id="${person.id}"
                data-person-type="Person">
                ${headshot}
                <div class="flex-1 min-w-0">
                    <div class="font-medium text-sm text-gray-900 truncate">${person.name}</div>
                    <div class="text-xs text-gray-500 truncate">${person.email || ''}</div>
                </div>
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5 text-gray-400">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
                </svg>
            </button>
        `;
    }

    renderGroupResult(group) {
        const headshot = group.headshot_url
            ? `<img src="${group.headshot_url}" alt="${group.name}" class="w-10 h-10 rounded-lg object-cover flex-shrink-0">`
            : `<div class="w-10 h-10 rounded-lg bg-purple-100 flex items-center justify-center text-purple-700 font-bold text-xs flex-shrink-0">${group.initials || ''}</div>`;

        return `
            <button type="button"
                class="w-full flex items-center gap-3 p-3 rounded-lg hover:bg-pink-50 transition-all cursor-pointer text-left"
                data-action="click->drop-role#selectPersonFromSearch"
                data-group-id="${group.id}"
                data-person-type="Group">
                ${headshot}
                <div class="flex-1 min-w-0">
                    <div class="font-medium text-sm text-gray-900 truncate">${group.name}</div>
                    <div class="text-xs text-purple-600">Group</div>
                </div>
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5 text-gray-400">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
                </svg>
            </button>
        `;
    }

    // Select a person from search results
    selectPersonFromSearch(event) {
        event.preventDefault();
        const button = event.currentTarget;
        const personId = button.dataset.personId;
        const groupId = button.dataset.groupId;
        const personType = button.dataset.personType;

        const roleId = this.hasAddPersonRoleIdTarget ? this.addPersonRoleIdTarget.value : null;

        if (!roleId) return;

        // Close modal
        this.closeAddPersonModal();

        // Assign the person/group
        const showId = this.showId;
        const productionId = this.productionId;

        const payload = {
            role_id: roleId
        };

        if (personType === 'Person' && personId) {
            payload.person_id = personId;
        } else if (personType === 'Group' && groupId) {
            payload.group_id = groupId;
        }

        fetch(`/manage/productions/${productionId}/casting/shows/${showId}/assign_person_to_role`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
            },
            body: JSON.stringify(payload)
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

                // Update linkage sync section if present
                if (data.linkage_sync_html) {
                    this.updateLinkageSyncSection(data.linkage_sync_html);
                }

                // Update progress bar and finalize section
                this.updateProgressBar(data.progress);
                this.updateFinalizeSection(data.finalize_section_html);
            })
            .catch(error => {
                console.error('Error assigning person:', error);
                alert('Failed to assign person. Please try again.');
            });
    }

    // Add a guest from the Add Person modal
    addGuestFromModal(event) {
        event.preventDefault();

        const guestName = this.hasAddPersonGuestNameTarget ? this.addPersonGuestNameTarget.value.trim() : '';
        const guestEmail = this.hasAddPersonGuestEmailTarget ? this.addPersonGuestEmailTarget.value.trim() : '';
        const roleId = this.hasAddPersonRoleIdTarget ? this.addPersonRoleIdTarget.value : null;

        if (!guestName) {
            this.addPersonGuestNameTarget?.focus();
            this.addPersonGuestNameTarget?.classList.add('border-pink-500');
            return;
        }

        if (!roleId) {
            alert('Please select a role first');
            return;
        }

        // Close modal
        this.closeAddPersonModal();

        const showId = this.showId;
        const productionId = this.productionId;

        fetch(`/manage/productions/${productionId}/casting/shows/${showId}/assign_guest_to_role`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
            },
            body: JSON.stringify({
                role_id: roleId,
                guest_name: guestName,
                guest_email: guestEmail
            })
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

                // Update linkage sync section if present
                if (data.linkage_sync_html) {
                    this.updateLinkageSyncSection(data.linkage_sync_html);
                }

                // Update progress bar and finalize section
                this.updateProgressBar(data.progress);
                this.updateFinalizeSection(data.finalize_section_html);
            })
            .catch(error => {
                console.error('Error assigning guest:', error);
                alert('Failed to add guest. Please try again.');
            });
    }

    // Submit guest assignment
    submitGuestAssignment(event) {
        event.preventDefault();
        const nameInput = document.getElementById('guest-name-input');
        const emailInput = document.getElementById('guest-email-input');
        const roleSelect = document.getElementById('guest-role-select');

        const guestName = nameInput?.value?.trim() || '';
        const guestEmail = emailInput?.value?.trim() || '';
        const roleId = roleSelect?.value || '';

        if (!guestName) {
            nameInput?.focus();
            nameInput?.classList.add('border-pink-500');
            return;
        }

        if (!roleId) {
            roleSelect?.focus();
            roleSelect?.classList.add('border-pink-500');
            return;
        }

        const showId = this.showId;
        const productionId = this.productionId;

        // Close modal immediately
        this.closeGuestModal();

        fetch(`/manage/productions/${productionId}/casting/shows/${showId}/assign_guest_to_role`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
            },
            body: JSON.stringify({
                role_id: roleId,
                guest_name: guestName,
                guest_email: guestEmail
            })
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

                // Update linkage sync section if present
                if (data.linkage_sync_html) {
                    this.updateLinkageSyncSection(data.linkage_sync_html);
                }

                // Update progress bar and finalize section
                this.updateProgressBar(data.progress);
                this.updateFinalizeSection(data.finalize_section_html);
            })
            .catch(error => {
                console.error('Error assigning guest:', error);
                alert('Failed to assign guest. Please try again.');
            });
    }

    // Assign from the mobile modal
    assignFromModal(event) {
        event.preventDefault();
        const button = event.currentTarget;
        const assignableType = button.dataset.assignableType;
        const assignableId = button.dataset.assignableId;
        const showId = this.showId;
        const productionId = this.productionId;
        const roleId = this.currentAssignRoleId;

        if (!roleId) return;

        const requestBody = { role_id: roleId };
        if (assignableType === "Person") {
            requestBody.person_id = assignableId;
        } else if (assignableType === "Group") {
            requestBody.group_id = assignableId;
        }

        // Close modal immediately
        this.closeAssignModal();

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

                // Update linkage sync section if present
                if (data.linkage_sync_html) {
                    this.updateLinkageSyncSection(data.linkage_sync_html);
                }

                // Update progress bar and finalize section
                this.updateProgressBar(data.progress);
                this.updateFinalizeSection(data.finalize_section_html);
            });
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

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

        const showId = this.showId;
        const productionId = this.productionId;

        // If dragging from an assignment (role-to-role), sourceRoleId will be set
        if (sourceRoleId && sourceRoleId !== roleId) {
            // Remove from source role first, then add to target role
            this.moveAssignment(productionId, showId, assignableId, sourceRoleId, roleId, assignableType);
        } else {
            // Dragging from cast members list - assign directly
            // For multi-slot roles, the backend checks if there's space
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
                    if (data.error) {
                        // Show error feedback (e.g., role is fully cast or already assigned)
                        roleElement.classList.add('ring-2', 'ring-red-400', 'bg-red-50');
                        setTimeout(() => {
                            roleElement.classList.remove('ring-2', 'ring-red-400', 'bg-red-50');
                        }, 500);
                        return;
                    }

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

                    // Update cast members list
                    if (data.cast_members_html) {
                        const castMembersList = document.getElementById("cast-members-list");
                        if (castMembersList) {
                            castMembersList.outerHTML = data.cast_members_html;
                        }
                    }

                    // Update linkage sync section if present
                    if (data.linkage_sync_html) {
                        this.updateLinkageSyncSection(data.linkage_sync_html);
                    }

                    // Update progress bar and finalize section
                    this.updateProgressBar(data.progress);
                    this.updateFinalizeSection(data.finalize_section_html);
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
        const showId = this.showId;
        const productionId = this.productionId;

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

                // Update linkage sync section if present
                if (data.linkage_sync_html) {
                    this.updateLinkageSyncSection(data.linkage_sync_html);
                }

                // Update progress bar and finalize section
                this.updateProgressBar(data.progress);
                this.updateFinalizeSection(data.finalize_section_html);
            });
    }

    moveAssignment(productionId, showId, assignableId, sourceRoleId, targetRoleId, assignableType) {
        // For multi-slot roles: remove from source, then assign to target
        // We need to find the specific assignment by assignable, not just by role

        // Find the assignment element to get its ID
        const assignmentEl = document.querySelector(`[data-source-role-id="${sourceRoleId}"][data-assignable-id="${assignableId}"]`);
        const assignmentId = assignmentEl?.dataset.assignmentId;

        const removeBody = assignmentId ? { assignment_id: assignmentId } : { role_id: sourceRoleId };

        // First, remove the entity from the source role
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
                if (data.error) {
                    // If target role is full, show error
                    console.error("Move failed:", data.error);
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

                // Update linkage sync section if present
                if (data.linkage_sync_html) {
                    this.updateLinkageSyncSection(data.linkage_sync_html);
                }

                // Update progress bar and finalize section
                this.updateProgressBar(data.progress);
                this.updateFinalizeSection(data.finalize_section_html);
            });
    }

    removeAssignment(event) {
        event.preventDefault();
        const assignmentId = event.currentTarget.dataset.assignmentId;
        const assignableType = event.currentTarget.dataset.assignableType;
        const assignableId = event.currentTarget.dataset.assignableId;
        const showId = this.showId;
        const productionId = this.productionId;

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
                // Update roles list
                if (data.roles_html) {
                    document.getElementById("show-roles").outerHTML = data.roles_html;
                }

                // Update cast members list (this properly reflects who is/isn't assigned)
                if (data.cast_members_html) {
                    const castMembersList = document.getElementById("cast-members-list");
                    if (castMembersList) {
                        castMembersList.outerHTML = data.cast_members_html;
                    }
                }

                // Update linkage sync section if present
                if (data.linkage_sync_html) {
                    this.updateLinkageSyncSection(data.linkage_sync_html);
                }

                // Update progress bar and finalize section
                this.updateProgressBar(data.progress);
                this.updateFinalizeSection(data.finalize_section_html);
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

        // Note: finalize section visibility is now controlled by the server response
        // via updateFinalizeSection - we don't try to show/hide it here based on
        // data attributes since the element may have been replaced
    }

    // Update the finalize section with fresh HTML from the server
    // If finalizeSectionHtml is provided, show it. If null/undefined, hide the section.
    updateFinalizeSection(finalizeSectionHtml) {
        const finalizeWrapper = document.getElementById('finalize-section-wrapper');
        if (finalizeWrapper) {
            if (finalizeSectionHtml) {
                finalizeWrapper.innerHTML = finalizeSectionHtml;
                finalizeWrapper.classList.remove('hidden');
            } else {
                finalizeWrapper.classList.add('hidden');
            }
        }
    }

    // Update the linkage sync section with fresh HTML from the server
    updateLinkageSyncSection(linkageSyncHtml) {
        const syncSection = document.getElementById('linkage-sync-section');
        if (syncSection && linkageSyncHtml) {
            syncSection.outerHTML = linkageSyncHtml;
        }
    }

    // Create a vacancy from an existing assignment
    createVacancy(event) {
        event.preventDefault();
        const button = event.currentTarget;
        const roleId = button.dataset.roleId;
        const showId = this.showId;
        const productionId = this.productionId;

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

                // Update linkage sync section if present
                if (data.linkage_sync_html) {
                    this.updateLinkageSyncSection(data.linkage_sync_html);
                }

                // Update progress bar and finalize section
                this.updateProgressBar(data.progress);
                this.updateFinalizeSection(data.finalize_section_html);
            });
    }
}
