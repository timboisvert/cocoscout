import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "role", "person", "show", "assignment", "assignModal", "rolesContainer",
        // Add Person modal targets
        "addPersonModal", "addPersonRoleName", "addPersonRoleId", "addPersonSlotPosition",
        "addPersonSearchTab", "addPersonGuestTab",
        "personSearchInput", "personSearchSpinner", "personSearchResults",
        "addPersonGuestName", "addPersonGuestEmail",
        // Restricted role warning modal targets
        "restrictedWarningModal", "restrictedWarningPersonName", "restrictedWarningRoleName",
        "restrictedWarningEligibleList", "restrictedWarningRoleId", "restrictedWarningAssignableType",
        "restrictedWarningAssignableId", "restrictedWarningSourceRoleId",
        "restrictedWarningGuestName", "restrictedWarningGuestEmail",
        // Replace assignment modal targets
        "replaceModal", "replaceModalTitle", "replaceNewPersonHeadshot", "replaceNewPersonName",
        "replaceNewPersonNameWarning", "replaceRoleName", "replaceEligibilityWarning", "replaceOptionsList",
        "replaceRoleId", "replaceAssignableType", "replaceAssignableId", "replaceSourceRoleId", "replaceIsEligible"
    ];
    static values = { showId: String, productionId: String, castingSource: String, clickToAdd: Boolean };

    connect() {
        // Close modal on escape key
        this.handleEscape = (event) => {
            if (event.key === 'Escape') {
                this.closeAssignModal();
                this.closeAddPersonModal();
                this.closeRestrictedWarningModal();
                this.closeReplaceModal();
            }
        };
        document.addEventListener('keydown', this.handleEscape);

        // Debounce timer for search
        this.searchTimeout = null;
    }

    disconnect() {
        document.removeEventListener('keydown', this.handleEscape);
    }

    // Helper to handle server errors - suppress expected ones, alert others
    handleServerError(error) {
        const suppressedErrors = [
            'already fully cast',
            'already assigned to this role',
            'not eligible for this restricted role'
        ];
        const shouldSuppress = suppressedErrors.some(msg => error.includes(msg));
        if (shouldSuppress) {
            console.warn('Suppressed error from server:', error);
        } else {
            alert(error);
        }
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

    // Restricted role warning modal methods
    showRestrictedWarningModal(roleElement, assignableType, assignableId, sourceRoleId = null, guestName = null, guestEmail = null) {
        if (!this.hasRestrictedWarningModalTarget) {
            // If modal not available, just proceed with assignment anyway
            console.warn("Restricted warning modal not found, proceeding with assignment");
            return;
        }

        const roleName = roleElement.dataset.roleName || "this role";
        const eligibleNames = JSON.parse(roleElement.dataset.eligibleMemberNames || "[]");
        const roleId = roleElement.dataset.roleId;

        // Get the person's name - either from guest info or by querying the DOM
        let personName;
        if (assignableType === "Guest" && guestName) {
            personName = guestName;
        } else {
            // Get from dragged element by querying the DOM directly
            // (elements use drag-cast-member controller, not drop-role)
            const draggedPerson = document.querySelector(
                `[data-person-id="${assignableId}"], [data-group-id="${assignableId}"]`
            );
            personName = draggedPerson?.dataset.personName || "Unknown";
        }

        // Fill in the modal content
        this.restrictedWarningPersonNameTarget.textContent = personName;
        this.restrictedWarningRoleNameTarget.textContent = roleName;

        // Show eligible members list
        if (eligibleNames.length > 0) {
            this.restrictedWarningEligibleListTarget.textContent = eligibleNames.join(", ");
        } else {
            this.restrictedWarningEligibleListTarget.textContent = "No one is currently approved";
        }

        // Store assignment data for confirmation
        this.restrictedWarningRoleIdTarget.value = roleId;
        this.restrictedWarningAssignableTypeTarget.value = assignableType;
        this.restrictedWarningAssignableIdTarget.value = assignableId || "";
        this.restrictedWarningSourceRoleIdTarget.value = sourceRoleId || "";

        // Store guest info if provided
        if (this.hasRestrictedWarningGuestNameTarget) {
            this.restrictedWarningGuestNameTarget.value = guestName || "";
        }
        if (this.hasRestrictedWarningGuestEmailTarget) {
            this.restrictedWarningGuestEmailTarget.value = guestEmail || "";
        }

        // Show the modal
        this.restrictedWarningModalTarget.classList.remove('hidden');
        document.body.classList.add('overflow-hidden');
    }

    closeRestrictedWarningModal() {
        if (!this.hasRestrictedWarningModalTarget) return;

        this.restrictedWarningModalTarget.classList.add('hidden');
        document.body.classList.remove('overflow-hidden');
    }

    confirmRestrictedAssignment() {
        const roleId = this.restrictedWarningRoleIdTarget.value;
        const assignableType = this.restrictedWarningAssignableTypeTarget.value;
        const assignableId = this.restrictedWarningAssignableIdTarget.value;
        const sourceRoleId = this.restrictedWarningSourceRoleIdTarget.value;
        const guestName = this.hasRestrictedWarningGuestNameTarget ? this.restrictedWarningGuestNameTarget.value : "";
        const guestEmail = this.hasRestrictedWarningGuestEmailTarget ? this.restrictedWarningGuestEmailTarget.value : "";

        this.closeRestrictedWarningModal();

        const showId = this.showId;
        const productionId = this.productionId;

        // If dragging from an assignment (role-to-role), sourceRoleId will be set
        if (sourceRoleId && sourceRoleId !== roleId) {
            this.moveAssignment(productionId, showId, assignableId, sourceRoleId, roleId, assignableType);
        } else if (assignableType === "Guest") {
            // Handle guest assignment to restricted role
            fetch(`/manage/productions/${productionId}/casting/shows/${showId}/assign_guest_to_role`, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
                },
                body: JSON.stringify({
                    role_id: roleId,
                    guest_name: guestName,
                    guest_email: guestEmail,
                    force: true
                })
            })
                .then(r => r.json())
                .then(data => {
                    if (data.error) {
                        this.handleServerError(data.error);
                    } else {
                        window.location.reload();
                    }
                })
                .catch(err => {
                    console.error('Failed to assign guest:', err);
                    alert('Failed to assign guest. Please try again.');
                });
        } else {
            // Assign directly (bypassing eligibility check since user confirmed)
            const requestBody = { role_id: roleId, force: true };
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
                        this.handleServerError(data.error);
                    } else {
                        window.location.reload();
                    }
                })
                .catch(err => {
                    console.error('Failed to assign:', err);
                    alert('Failed to assign. Please try again.');
                });
        }
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

        // Find the role element to check eligibility
        const roleElement = document.querySelector(`[data-role-id="${roleId}"]`);
        const isRestricted = roleElement?.dataset.roleRestricted === "true";
        const assignableId = personType === 'Person' ? personId : groupId;

        // Check eligibility for restricted roles
        if (isRestricted && roleElement) {
            const isEligible = this.isEligibleForRole(roleElement, personType, assignableId);
            if (!isEligible) {
                // Close the add person modal and show the restricted warning modal
                this.closeAddPersonModal();
                this.showRestrictedWarningModal(roleElement, personType, assignableId, null);
                return;
            }
        }

        // Close modal
        this.closeAddPersonModal();

        // Assign the person/group
        this.performAssignmentFromModal(roleId, personType, personId, groupId);
    }

    // Perform assignment from modal (after eligibility check passed or user confirmed)
    performAssignmentFromModal(roleId, personType, personId, groupId) {
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
                    this.handleServerError(data.error);
                    return;
                }

                // Update roles list
                if (data.roles_html) {
                    document.getElementById("show-roles").outerHTML = data.roles_html;
                }

                // Update cast members list
                if (data.cast_members_html) {
                    const castMembersList = document.getElementById("show-cast-members");
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

        // Check if role is restricted - show warning modal if so
        const roleElement = document.querySelector(`[data-role-id="${roleId}"]`);
        const isRestricted = roleElement?.dataset.roleRestricted === "true";
        if (isRestricted) {
            // Close the add person modal first
            this.closeAddPersonModal();
            // Show the restricted warning modal for guests
            this.showRestrictedWarningModal(roleElement, "Guest", null, null, guestName, guestEmail);
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
                    this.handleServerError(data.error);
                    return;
                }

                // Update roles list
                if (data.roles_html) {
                    document.getElementById("show-roles").outerHTML = data.roles_html;
                }

                // Update cast members list
                if (data.cast_members_html) {
                    const castMembersList = document.getElementById("show-cast-members");
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
                    this.handleServerError(data.error);
                    return;
                }

                // Update roles list
                if (data.roles_html) {
                    document.getElementById("show-roles").outerHTML = data.roles_html;
                }

                // Update cast members list
                if (data.cast_members_html) {
                    const castMembersList = document.getElementById("show-cast-members");
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
                    const castMembersList = document.getElementById("show-cast-members");
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

        // Get role info
        const roleQuantity = parseInt(roleElement.dataset.roleQuantity || "1", 10);
        const roleFilled = parseInt(roleElement.dataset.roleFilled || "0", 10);
        const isRestricted = roleElement.dataset.roleRestricted === "true";
        const isEligible = this.isEligibleForRole(roleElement, assignableType, assignableId);
        const currentAssignments = JSON.parse(roleElement.dataset.currentAssignments || "[]");

        // Check if this person/group is already assigned to this role - if so, do nothing (no-op)
        const alreadyAssigned = currentAssignments.some(a =>
            a.type === assignableType && String(a.assignableId) === String(assignableId)
        );
        if (alreadyAssigned) {
            // Silently ignore - person is already in this role
            console.log('Person already assigned to this role, ignoring');
            return;
        }

        // Check if the role is fully filled
        const isRoleFull = roleFilled >= roleQuantity;

        // If role is full, we need to handle replacement logic
        if (isRoleFull) {
            // Get person's info for the modal by querying the DOM directly
            // (elements use drag-cast-member controller, not drop-role)
            const draggedPerson = document.querySelector(
                `[data-person-id="${assignableId}"], [data-group-id="${assignableId}"]`
            );
            const personName = draggedPerson?.dataset.personName || "Unknown";
            const personInitials = draggedPerson?.dataset.personInitials || this.getInitials(personName);
            const personHeadshotUrl = draggedPerson?.dataset.personHeadshotUrl || "";

            if (roleQuantity === 1) {
                // Single-person role: Auto-replace
                const existingAssignment = currentAssignments[0];
                if (existingAssignment) {
                    // If restricted and not eligible, show warning first
                    if (isRestricted && !isEligible) {
                        this.showReplaceModal(roleElement, assignableType, assignableId, sourceRoleId, personName, personInitials, personHeadshotUrl, isEligible, currentAssignments);
                        return;
                    }
                    // Do the replacement directly
                    this.replaceAssignment(existingAssignment.id, assignableType, assignableId, roleId, sourceRoleId);
                }
            } else {
                // Multi-person role: Show modal with options
                this.showReplaceModal(roleElement, assignableType, assignableId, sourceRoleId, personName, personInitials, personHeadshotUrl, isEligible, currentAssignments);
            }
            return;
        }

        // Role has space - check eligibility for restricted roles
        if (isRestricted && !isEligible) {
            // Show warning modal instead of rejecting
            this.showRestrictedWarningModal(roleElement, assignableType, assignableId, sourceRoleId);
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
            this.performAssignment(roleId, assignableType, assignableId);
        }
    }

    // Perform the actual assignment API call
    performAssignment(roleId, assignableType, assignableId, force = false) {
        const showId = this.showId;
        const productionId = this.productionId;

        const requestBody = { role_id: roleId, force: force };
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
                    this.handleServerError(data.error);
                    return;
                }

                // Update UI
                this.updateUIAfterAssignment(data, assignableType, assignableId);
            });
    }

    // Update UI after a successful assignment
    updateUIAfterAssignment(data, assignableType, assignableId) {
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
            const castMembersList = document.getElementById("show-cast-members");
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
    }

    // Show the replace modal for full roles
    showReplaceModal(roleElement, assignableType, assignableId, sourceRoleId, personName, personInitials, personHeadshotUrl, isEligible, currentAssignments) {
        if (!this.hasReplaceModalTarget) {
            console.warn("Replace modal not found");
            return;
        }

        const roleName = roleElement.dataset.roleName || "this role";
        const roleId = roleElement.dataset.roleId;
        const roleQuantity = parseInt(roleElement.dataset.roleQuantity || "1", 10);

        // Fill in new person's info with headshot
        this.replaceNewPersonNameTarget.textContent = personName;
        if (this.hasReplaceNewPersonNameWarningTarget) {
            this.replaceNewPersonNameWarningTarget.textContent = personName;
        }
        this.replaceRoleNameTarget.textContent = roleName;

        // Set headshot or initials for the new person
        if (personHeadshotUrl) {
            this.replaceNewPersonHeadshotTarget.innerHTML = `<img src="${personHeadshotUrl}" alt="${personName}" class="w-12 h-12 object-cover rounded-lg">`;
        } else {
            this.replaceNewPersonHeadshotTarget.innerHTML = `<span>${personInitials}</span>`;
        }

        // Show/hide eligibility warning
        if (!isEligible) {
            this.replaceEligibilityWarningTarget.classList.remove('hidden');
        } else {
            this.replaceEligibilityWarningTarget.classList.add('hidden');
        }

        // Store data in hidden fields
        this.replaceRoleIdTarget.value = roleId;
        this.replaceAssignableTypeTarget.value = assignableType;
        this.replaceAssignableIdTarget.value = assignableId;
        this.replaceSourceRoleIdTarget.value = sourceRoleId || "";
        this.replaceIsEligibleTarget.value = isEligible ? "true" : "false";

        // Build options list
        let optionsHtml = '';

        // Option to replace each current assignment
        currentAssignments.forEach((assignment, index) => {
            const assignmentInitials = assignment.initials || this.getInitials(assignment.name);
            const headshotHtml = assignment.headshotUrl
                ? `<img src="${assignment.headshotUrl}" alt="${assignment.name}" class="w-10 h-10 object-cover rounded-full">`
                : `<span>${assignmentInitials}</span>`;

            optionsHtml += `
                <button type="button"
                        class="w-full text-left px-4 py-3 border border-gray-200 rounded-lg hover:border-pink-300 hover:bg-pink-50 transition-all cursor-pointer group"
                        data-action="click->drop-role#executeReplace"
                        data-replace-assignment-id="${assignment.id}"
                        data-replace-type="replace">
                    <div class="flex items-center gap-3">
                        <div class="w-10 h-10 rounded-full bg-gray-200 flex items-center justify-center text-xs font-medium text-gray-600 flex-shrink-0 overflow-hidden">
                            ${headshotHtml}
                        </div>
                        <div class="flex-1">
                            <span class="text-sm font-medium text-gray-900 group-hover:text-pink-700">Replace ${assignment.name}</span>
                            <p class="text-xs text-gray-500">${assignment.name} will be removed from this role</p>
                        </div>
                        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5 text-gray-400 group-hover:text-pink-500">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M8.25 4.5l7.5 7.5-7.5 7.5" />
                        </svg>
                    </div>
                </button>
            `;
        });

        this.replaceOptionsListTarget.innerHTML = optionsHtml;

        // Update title based on situation
        if (roleQuantity === 1) {
            this.replaceModalTitleTarget.textContent = "Replace Assignment";
        } else {
            this.replaceModalTitleTarget.textContent = "Role is Full";
        }

        // Show modal
        this.replaceModalTarget.classList.remove('hidden');
        document.body.classList.add('overflow-hidden');
    }

    // Close replace modal
    closeReplaceModal() {
        if (!this.hasReplaceModalTarget) return;
        this.replaceModalTarget.classList.add('hidden');
        document.body.classList.remove('overflow-hidden');
    }

    // Execute the replace action
    executeReplace(event) {
        const button = event.currentTarget;
        const replaceAssignmentId = button.dataset.replaceAssignmentId;

        const roleId = this.replaceRoleIdTarget.value;
        const assignableType = this.replaceAssignableTypeTarget.value;
        const assignableId = this.replaceAssignableIdTarget.value;
        const sourceRoleId = this.replaceSourceRoleIdTarget.value;

        this.closeReplaceModal();

        this.replaceAssignment(replaceAssignmentId, assignableType, assignableId, roleId, sourceRoleId);
    }

    // Replace an existing assignment with a new one
    replaceAssignment(existingAssignmentId, newAssignableType, newAssignableId, roleId, sourceRoleId) {
        const showId = this.showId;
        const productionId = this.productionId;

        const requestBody = {
            assignment_id: existingAssignmentId,
            role_id: roleId,
            force: true // Allow non-eligible for restricted roles (user confirmed)
        };
        if (newAssignableType === "Person") {
            requestBody.new_person_id = newAssignableId;
        } else if (newAssignableType === "Group") {
            requestBody.new_group_id = newAssignableId;
        }

        // If we're moving from another role, include source info
        if (sourceRoleId && sourceRoleId !== roleId) {
            requestBody.source_role_id = sourceRoleId;
        }

        fetch(`/manage/productions/${productionId}/casting/shows/${showId}/replace_assignment`, {
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
                    this.handleServerError(data.error);
                    return;
                }

                // Update UI
                this.updateUIAfterAssignment(data, newAssignableType, newAssignableId);
            });
    }

    // Get initials from a name
    getInitials(name) {
        if (!name) return "?";
        return name.split(" ").map(n => n[0]).join("").toUpperCase().slice(0, 2);
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
                    const castMembersList = document.getElementById("show-cast-members");
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
                    const castMembersList = document.getElementById("show-cast-members");
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
                    const castMembersList = document.getElementById("show-cast-members");
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
                    this.handleServerError(data.error);
                    return;
                }

                // Update roles list
                if (data.roles_html) {
                    document.getElementById("show-roles").outerHTML = data.roles_html;
                }

                // Update cast members list
                if (data.cast_members_html) {
                    const castMembersList = document.getElementById("show-cast-members");
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
