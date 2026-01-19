import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "modal", "loading", "emptyState", "rolesListSection", "rolesList",
        "roleForm", "formTitle", "roleNameInput", "roleNameError",
        "restrictedCheckbox", "eligibleMembersSection", "memberSearchInput", "membersList",
        "saveButtonText", "modalFooter", "customRolesCheckbox", "customRolesContent",
        "deleteConfirmModal", "deleteConfirmMessage", "inlineRolesList", "manageButton",
        "migrationModal", "migrationSubtitle", "migrationLoading", "migrationContent",
        "migrationSummary", "migrationSummaryText", "linkedShowsWarning", "linkedShowsText",
        "autoMappableSection", "autoMappableList", "needsDecisionSection", "needsDecisionList",
        "noAssignmentsMessage", "migrationStats", "migrationExecuteButton", "migrationHint",
        "quantityInput", "categorySelect",
        "slotChangeModal", "slotChangeTitle", "slotChangeMessage", "slotChangeList",
        "slotChangeStats", "slotChangeExecuteButton"
    ]

    static values = {
        showId: Number,
        productionId: Number,
        rolesUrl: String,
        copyUrl: String,
        reorderUrl: String,
        talentPoolUrl: String,
        checkAssignmentsUrl: String,
        clearAssignmentsUrl: String,
        toggleUrl: String,
        migrationPreviewUrl: String,
        executeMigrationUrl: String,
        usingCustomRoles: Boolean
    }

    connect() {
        this.editingRoleId = null
        this.roles = []
        this.talentPoolMembers = []
        this.selectedMemberKeys = []
        this.pendingDeleteRoleId = null
        this.pendingToggleTo = null
        this.migrationData = null
        this.roleMappings = {} // {assignment_id: {target_role_id, action}}
        this.slotChangeData = null // For slot quantity change migrations
        this.selectedKeepAssignments = new Set() // Assignment IDs to keep during slot reduction

        this.boundHandleKeydown = this.handleKeydown.bind(this)
        document.addEventListener("keydown", this.boundHandleKeydown)
    }

    disconnect() {
        document.removeEventListener("keydown", this.boundHandleKeydown)
    }

    handleKeydown(event) {
        if (event.key === "Escape") {
            if (this.hasSlotChangeModalTarget && !this.slotChangeModalTarget.classList.contains("hidden")) {
                this.cancelSlotChange()
            } else if (this.hasMigrationModalTarget && !this.migrationModalTarget.classList.contains("hidden")) {
                this.cancelMigration()
            } else if (!this.deleteConfirmModalTarget.classList.contains("hidden")) {
                this.cancelDelete()
            } else if (!this.modalTarget.classList.contains("hidden")) {
                this.closeModal()
            }
        }
    }

    // Toggle custom roles on/off
    async toggleCustomRoles() {
        const enabled = this.customRolesCheckboxTarget.checked
        console.log("[Migration] Toggle triggered, enabled:", enabled)

        // Always check migration preview to get assignment count and whether custom roles exist
        if (this.hasMigrationPreviewUrlValue) {
            try {
                const url = `${this.migrationPreviewUrlValue}?switching_to=${enabled ? 'custom' : 'production'}`
                console.log("[Migration] Fetching:", url)

                const response = await fetch(url, {
                    headers: {
                        "Accept": "application/json",
                        "X-CSRF-Token": this.csrfToken
                    }
                })
                const data = await response.json()
                console.log("[Migration] Response data:", data)

                // Always show migration modal when there are assignments
                // This gives the user visibility into what will happen, even if all roles match
                if (data.total_assignments > 0) {
                    console.log("[Migration] Showing modal - has assignments")
                    this.pendingToggleTo = enabled
                    this.migrationData = data
                    this.showMigrationModal(data)
                    this.customRolesCheckboxTarget.checked = !enabled
                    return
                }

                // Also show for linked shows even without assignments
                if (data.is_linked && data.linked_shows.length > 0) {
                    console.log("[Migration] Showing modal - is linked")
                    this.pendingToggleTo = enabled
                    this.migrationData = data
                    this.showMigrationModal(data)
                    this.customRolesCheckboxTarget.checked = !enabled
                    return
                }

                console.log("[Migration] No assignments, proceeding with toggle")
            } catch (error) {
                console.error("[Migration] Failed to check assignments:", error)
            }
        }

        // No assignments or fallback, toggle visibility and persist the change
        this.applyToggleState(enabled, true)
    }

    // Apply the toggle state (show/hide custom roles content)
    async applyToggleState(enabled, persistChange = false) {
        if (enabled) {
            this.customRolesContentTarget.classList.remove("hidden")
        } else {
            this.customRolesContentTarget.classList.add("hidden")
        }

        // Persist the change if requested and we have the toggle URL
        if (persistChange && this.hasToggleUrlValue) {
            try {
                await fetch(this.toggleUrlValue, {
                    method: "POST",
                    headers: {
                        "Accept": "application/json",
                        "Content-Type": "application/json",
                        "X-CSRF-Token": this.csrfToken
                    },
                    body: JSON.stringify({ enable: enabled })
                })
                // Reload roles after toggle
                if (enabled) {
                    this.loadRoles()
                }
            } catch (error) {
                console.error("Failed to toggle custom roles:", error)
            }
        }
    }

    // Show the migration modal with preview data
    showMigrationModal(data) {
        if (!this.hasMigrationModalTarget) return

        // Reset mappings
        this.roleMappings = {}

        // Update subtitle based on direction
        const direction = data.switching_to === 'custom' ? 'custom roles' : 'production roles'
        if (this.hasMigrationSubtitleTarget) {
            this.migrationSubtitleTarget.textContent = `Switching to ${direction}`
        }

        // Show hint about editing roles when switching TO custom roles
        if (this.hasMigrationHintTarget) {
            if (data.switching_to === 'custom') {
                this.migrationHintTarget.classList.remove("hidden")
            } else {
                this.migrationHintTarget.classList.add("hidden")
            }
        }

        // Show/hide sections based on data
        this.migrationLoadingTarget.classList.add("hidden")
        this.migrationContentTarget.classList.remove("hidden")

        // Handle linked shows warning
        if (data.is_linked && data.linked_shows.length > 0) {
            this.linkedShowsWarningTarget.classList.remove("hidden")
            const showNames = data.linked_shows.map(s => s.title).join(", ")
            this.linkedShowsTextTarget.textContent = `This will also affect: ${showNames}`
        } else {
            this.linkedShowsWarningTarget.classList.add("hidden")
        }

        // Build the assignment lists
        const autoMappable = data.mappings.filter(m => m.can_auto_map)
        const needsDecision = data.mappings.filter(m => !m.can_auto_map)

        // Auto-mappable section
        if (autoMappable.length > 0) {
            this.autoMappableSectionTarget.classList.remove("hidden")
            this.autoMappableListTarget.innerHTML = autoMappable.map(m => this.buildAutoMappableRow(m)).join("")
        } else {
            this.autoMappableSectionTarget.classList.add("hidden")
        }

        // Needs decision section
        if (needsDecision.length > 0) {
            this.needsDecisionSectionTarget.classList.remove("hidden")
            this.needsDecisionListTarget.innerHTML = needsDecision.map(m => this.buildNeedsDecisionRow(m, data.target_roles)).join("")

            // Initialize dropdowns with remove action
            needsDecision.forEach(m => {
                this.roleMappings[m.assignment_id] = { action: 'remove', target_role_id: null }
            })
        } else {
            this.needsDecisionSectionTarget.classList.add("hidden")
        }

        // No assignments state
        if (data.total_assignments === 0) {
            this.noAssignmentsMessageTarget.classList.remove("hidden")
            this.autoMappableSectionTarget.classList.add("hidden")
            this.needsDecisionSectionTarget.classList.add("hidden")
            this.migrationSummaryTarget.classList.add("hidden")
        } else {
            this.noAssignmentsMessageTarget.classList.add("hidden")
            this.migrationSummaryTarget.classList.remove("hidden")
        }

        // Update stats
        this.updateMigrationStats(autoMappable.length, needsDecision.length)

        // Show the modal
        this.migrationModalTarget.classList.remove("hidden")
    }

    // Build a row for an auto-mappable assignment
    buildAutoMappableRow(mapping) {
        const avatar = mapping.headshot_url
            ? `<img src="${mapping.headshot_url}" alt="${mapping.assignable_name}" class="w-10 h-10 rounded-lg object-cover flex-shrink-0">`
            : `<div class="w-10 h-10 rounded-lg bg-gray-200 flex items-center justify-center text-gray-700 font-bold text-sm flex-shrink-0">${mapping.initials}</div>`

        return `
            <div class="flex items-center gap-3 p-3 bg-gray-50 border border-gray-200 rounded-lg">
                ${avatar}
                <div class="flex-1 min-w-0">
                    <p class="font-medium text-gray-900 truncate">${mapping.assignable_name}</p>
                    <p class="text-sm text-gray-600">
                        <span class="text-gray-500">${mapping.current_role_name}</span>
                        <svg class="inline w-4 h-4 mx-1 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7l5 5m0 0l-5 5m5-5H6" />
                        </svg>
                        <span class="text-gray-700 font-medium">${mapping.suggested_target_role_name}</span>
                    </p>
                </div>
                <svg class="w-5 h-5 text-green-500 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                </svg>
            </div>
        `
    }

    // Build a row for an assignment needing decision
    buildNeedsDecisionRow(mapping, targetRoles) {
        const avatar = mapping.headshot_url
            ? `<img src="${mapping.headshot_url}" alt="${mapping.assignable_name}" class="w-10 h-10 rounded-lg object-cover flex-shrink-0">`
            : `<div class="w-10 h-10 rounded-lg bg-gray-200 flex items-center justify-center text-gray-700 font-bold text-sm flex-shrink-0">${mapping.initials}</div>`

        const roleOptions = targetRoles.map(r =>
            `<option value="${r.id}">${r.name}${r.category !== 'performing' ? ` (${r.category})` : ''}</option>`
        ).join("")

        return `
            <div class="flex items-center gap-3 p-3 bg-amber-50 border border-amber-200 rounded-lg">
                ${avatar}
                <div class="flex-1 min-w-0">
                    <p class="font-medium text-gray-900 truncate">${mapping.assignable_name}</p>
                    <p class="text-sm text-gray-600">
                        Currently: <span class="text-amber-700 font-medium">${mapping.current_role_name}</span>
                        <span class="text-gray-400 ml-1">(no matching role found)</span>
                    </p>
                </div>
                <select class="text-sm border border-gray-300 rounded-lg px-2 py-1.5 bg-white min-w-[140px]"
                        data-assignment-id="${mapping.assignment_id}"
                        data-action="change->show-roles-modal#updateRoleMapping">
                    <option value="remove" selected>Remove from cast</option>
                    <option disabled>──────────</option>
                    <option value="" disabled>Assign to role:</option>
                    ${roleOptions}
                </select>
            </div>
        `
    }

    // Handle dropdown change for role mapping
    updateRoleMapping(event) {
        const select = event.target
        const assignmentId = parseInt(select.dataset.assignmentId)
        const value = select.value

        if (value === 'remove') {
            this.roleMappings[assignmentId] = { action: 'remove', target_role_id: null }
        } else {
            this.roleMappings[assignmentId] = { action: 'transfer', target_role_id: parseInt(value) }
        }

        this.updateMigrationStats()
    }

    // Update the stats display in the migration modal footer
    updateMigrationStats(autoMappableCount = null, needsDecisionCount = null) {
        if (!this.hasMigrationStatsTarget) return

        if (autoMappableCount === null && this.migrationData) {
            autoMappableCount = this.migrationData.mappings.filter(m => m.can_auto_map).length
            needsDecisionCount = this.migrationData.mappings.filter(m => !m.can_auto_map).length
        }

        // Count how many from "needs decision" will be kept vs removed
        let keptCount = autoMappableCount || 0
        let removedCount = 0

        Object.values(this.roleMappings).forEach(mapping => {
            if (mapping.action === 'remove') {
                removedCount++
            } else {
                keptCount++
            }
        })

        const parts = []
        if (keptCount > 0) parts.push(`${keptCount} will transfer`)
        if (removedCount > 0) parts.push(`${removedCount} will be removed`)

        this.migrationStatsTarget.textContent = parts.join(", ") || "No changes"
    }

    // Execute the migration
    async executeMigration() {
        if (!this.hasExecuteMigrationUrlValue) return

        // Disable button during request
        if (this.hasMigrationExecuteButtonTarget) {
            this.migrationExecuteButtonTarget.disabled = true
            this.migrationExecuteButtonTarget.textContent = "Transferring..."
        }

        try {
            // Build role_mappings array from our tracking object
            const roleMappings = Object.entries(this.roleMappings).map(([assignmentId, mapping]) => ({
                assignment_id: parseInt(assignmentId),
                target_role_id: mapping.target_role_id,
                action: mapping.action
            }))

            const response = await fetch(this.executeMigrationUrlValue, {
                method: "POST",
                headers: {
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                    "X-CSRF-Token": this.csrfToken
                },
                body: JSON.stringify({
                    switching_to: this.pendingToggleTo ? 'custom' : 'production',
                    role_mappings: roleMappings,
                    apply_to_linked: true
                })
            })

            const data = await response.json()

            if (data.success) {
                // Save the toggle direction before canceling (which resets pendingToggleTo)
                const switchingToCustom = this.pendingToggleTo

                // Update the checkbox and content visibility
                this.customRolesCheckboxTarget.checked = switchingToCustom
                this.applyToggleState(switchingToCustom, false)

                // Close the migration modal
                this.cancelMigration()

                // If switching TO custom roles, stay in the casting settings modal so user can edit roles
                // Otherwise reload the page
                if (switchingToCustom) {
                    // Reload the roles list to show custom roles
                    this.loadRoles()
                } else {
                    // Switching to production roles - reload the page
                    window.location.reload()
                }
            } else {
                alert(data.error || "Failed to transfer assignments. Please try again.")
            }
        } catch (error) {
            console.error("Failed to execute migration:", error)
            alert("Failed to transfer assignments. Please try again.")
        } finally {
            if (this.hasMigrationExecuteButtonTarget) {
                this.migrationExecuteButtonTarget.disabled = false
                this.migrationExecuteButtonTarget.textContent = "Transfer Assignments"
            }
        }
    }

    // Cancel the migration
    cancelMigration() {
        if (this.hasMigrationModalTarget) {
            this.migrationModalTarget.classList.add("hidden")
        }
        this.pendingToggleTo = null
        this.migrationData = null
        this.roleMappings = {}
    }

    // Open the modal
    openModal(event) {
        if (event) event.preventDefault()
        this.modalTarget.classList.remove("hidden")
        this.loadRoles()
    }

    // Close the modal
    closeModal() {
        this.modalTarget.classList.add("hidden")
        this.hideForm()
        // The inline roles list is updated dynamically, so no need to reload
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    // Load roles from server
    async loadRoles() {
        this.showLoading()

        try {
            const response = await fetch(this.rolesUrlValue, {
                headers: {
                    "Accept": "application/json",
                    "X-CSRF-Token": this.csrfToken
                }
            })
            const data = await response.json()
            this.roles = data
            this.renderRoles()
        } catch (error) {
            console.error("Failed to load roles:", error)
        } finally {
            this.hideLoading()
        }
    }

    // Render roles list
    renderRoles() {
        if (this.roles.length === 0) {
            this.emptyStateTarget.classList.remove("hidden")
            this.rolesListSectionTarget.classList.add("hidden")
        } else {
            this.emptyStateTarget.classList.add("hidden")
            this.rolesListSectionTarget.classList.remove("hidden")
            this.rolesListTarget.innerHTML = this.roles.map(role => this.roleTemplate(role)).join("")
        }
        // Also update the inline roles list on the edit page
        this.updateInlineRolesList()
    }

    // Update the compact inline roles display on the edit page
    updateInlineRolesList() {
        if (!this.hasInlineRolesListTarget) return

        if (this.roles.length === 0) {
            this.inlineRolesListTarget.innerHTML = `<p class="text-sm text-gray-500 italic">No custom roles defined yet. Click "Manage Custom Roles" to add some.</p>`
        } else {
            const rolesHtml = this.roles.map(role => {
                const quantity = role.quantity || 1
                const quantityText = quantity > 1 ? `<span class="ml-1.5 text-gray-400">x ${quantity}</span>` : ""
                const restrictedIcon = role.restricted
                    ? `<svg class="ml-1 w-3.5 h-3.5 text-pink-500" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                         <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25Z" />
                       </svg>`
                    : ""
                return `<span class="inline-flex items-center px-3 py-1 rounded text-sm font-medium bg-gray-100 text-gray-800">${role.name}${quantityText}${restrictedIcon}</span>`
            }).join("")

            this.inlineRolesListTarget.innerHTML = `<div class="flex flex-wrap gap-2">${rolesHtml}</div>`
        }
    }

    roleTemplate(role) {
        const quantity = role.quantity || 1
        const assignmentsText = `<span class="text-xs text-gray-500">${role.assignments_count || 0}/${quantity} filled</span>`

        const restrictedBadge = role.restricted
            ? `<span class="ml-2 inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-yellow-100 text-yellow-800">Restricted</span>`
            : ""

        const categoryBadge = `<span class="text-xs font-medium text-gray-500 capitalize">${role.category || 'performing'}</span>`

        const eligibleMembers = role.restricted && role.eligible_members.length > 0
            ? `<div class="flex items-center gap-1 mt-2">
                <span class="text-gray-400 mr-1" title="Restricted role">
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25Z" />
                    </svg>
                </span>
                ${role.eligible_members.slice(0, 5).map(m => this.memberAvatarTemplate(m)).join("")}
                ${role.eligible_members.length > 5 ? `<span class="text-xs text-gray-500">+${role.eligible_members.length - 5} more</span>` : ""}
               </div>`
            : ""

        return `
            <div class="p-4 bg-white border border-gray-200 rounded-lg hover:border-gray-400 transition-all flex cursor-move group relative"
                 draggable="true"
                 data-role-id="${role.id}"
                 data-action="dragstart->show-roles-modal#startDrag dragend->show-roles-modal#endDrag dragover->show-roles-modal#dragOver dragleave->show-roles-modal#dragLeave drop->show-roles-modal#drop">
                <div class="flex items-center gap-4 w-full">
                    <span class="text-gray-400 cursor-move" title="Drag to reorder">
                        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 9h16.5m-16.5 6.75h16.5" />
                        </svg>
                    </span>
                    <div class="flex-1">
                        <div class="font-bold text-md flex items-center">
                            ${role.name}${quantity > 1 ? ` <span class="ml-1 text-sm font-normal text-gray-500">(${quantity} slots)</span>` : ''}
                            ${restrictedBadge}
                        </div>
                        <div class="flex items-center gap-2 mt-1">
                            ${categoryBadge}
                        </div>
                        ${eligibleMembers}
                    </div>
                    ${assignmentsText}
                    <div class="flex gap-2 items-center opacity-0 group-hover:opacity-100 transition-opacity">
                        <button type="button" data-action="click->show-roles-modal#editRole" data-role-id="${role.id}"
                                class="inline-flex items-center justify-center gap-2 font-medium rounded transition-colors cursor-pointer whitespace-nowrap bg-pink-500 hover:bg-pink-600 text-white px-3 py-1.5 text-sm">Edit Role</button>
                        <button type="button" data-action="click->show-roles-modal#deleteRole" data-role-id="${role.id}"
                                class="inline-flex items-center justify-center gap-2 font-medium rounded transition-colors cursor-pointer whitespace-nowrap bg-pink-500 hover:bg-pink-600 text-white px-3 py-1.5 text-sm">Delete Role</button>
                    </div>
                </div>
            </div>
        `
    }

    memberAvatarTemplate(member) {
        if (member.headshot_url) {
            return `<img src="${member.headshot_url}" alt="${member.name}" class="w-8 h-8 rounded-lg object-cover" title="${member.name}">`
        } else {
            return `<div class="w-8 h-8 rounded-lg bg-gray-200 flex items-center justify-center text-gray-700 font-bold text-xs" title="${member.name}">${member.initials}</div>`
        }
    }

    // Copy roles from production
    async copyFromProduction() {
        this.showLoading()

        try {
            const response = await fetch(this.copyUrlValue, {
                method: "POST",
                headers: {
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                    "X-CSRF-Token": this.csrfToken
                }
            })
            const data = await response.json()

            if (data.success) {
                this.roles = data.roles
                this.renderRoles()
            } else {
                alert(data.message || "Failed to copy roles")
            }
        } catch (error) {
            console.error("Failed to copy roles:", error)
            alert("Failed to copy roles. Please try again.")
        } finally {
            this.hideLoading()
        }
    }

    // Show add/edit form
    showAddForm() {
        this.editingRoleId = null
        this.roleNameInputTarget.value = ""
        this.restrictedCheckboxTarget.checked = false
        this.selectedMemberKeys = []
        this.formTitleTarget.textContent = "Add Role"
        this.saveButtonTextTarget.textContent = "Add Role"
        this.hideRoleNameError()
        this.updateEligibleMembersVisibility()

        // Reset quantity and category fields
        if (this.hasQuantityInputTarget) this.quantityInputTarget.value = "1"
        if (this.hasCategorySelectTarget) this.categorySelectTarget.value = "performing"

        this.showForm()
    }

    // Edit existing role
    editRole(event) {
        const roleId = parseInt(event.currentTarget.dataset.roleId)
        const role = this.roles.find(r => r.id === roleId)

        if (!role) return

        this.editingRoleId = roleId
        this.roleNameInputTarget.value = role.name
        this.restrictedCheckboxTarget.checked = role.restricted
        this.selectedMemberKeys = role.eligible_member_keys || []
        this.formTitleTarget.textContent = "Edit Role"
        this.saveButtonTextTarget.textContent = "Update Role"
        this.hideRoleNameError()
        this.updateEligibleMembersVisibility()

        // Populate quantity and category fields
        if (this.hasQuantityInputTarget) this.quantityInputTarget.value = role.quantity || 1
        if (this.hasCategorySelectTarget) this.categorySelectTarget.value = role.category || "performing"

        this.showForm()
    }

    showForm() {
        this.emptyStateTarget.classList.add("hidden")
        this.rolesListSectionTarget.classList.add("hidden")
        this.roleFormTarget.classList.remove("hidden")
        this.modalFooterTarget.classList.add("hidden")
        this.roleNameInputTarget.focus()
    }

    hideForm() {
        this.roleFormTarget.classList.add("hidden")
        this.modalFooterTarget.classList.remove("hidden")
        this.renderRoles()
    }

    cancelForm() {
        this.hideForm()
    }

    // Toggle restricted checkbox
    toggleRestricted() {
        this.updateEligibleMembersVisibility()
    }

    updateEligibleMembersVisibility() {
        if (this.restrictedCheckboxTarget.checked) {
            this.eligibleMembersSectionTarget.classList.remove("hidden")
            this.loadTalentPoolMembers()
        } else {
            this.eligibleMembersSectionTarget.classList.add("hidden")
        }
    }

    // Load talent pool members
    async loadTalentPoolMembers() {
        if (this.talentPoolMembers.length > 0) {
            this.renderMembers()
            return
        }

        try {
            const response = await fetch(this.talentPoolUrlValue, {
                headers: {
                    "Accept": "application/json",
                    "X-CSRF-Token": this.csrfToken
                }
            })
            this.talentPoolMembers = await response.json()
            this.renderMembers()
        } catch (error) {
            console.error("Failed to load talent pool members:", error)
        }
    }

    renderMembers() {
        if (this.talentPoolMembers.length === 0) {
            this.membersListTarget.innerHTML = `<p class="px-3 py-4 text-center text-gray-500 text-sm italic">No cast members in talent pools yet.</p>`
            return
        }

        this.membersListTarget.innerHTML = this.talentPoolMembers.map(member => {
            const checked = this.selectedMemberKeys.includes(member.key) ? "checked" : ""
            const avatar = member.headshot_url
                ? `<img src="${member.headshot_url}" alt="${member.name}" class="w-6 h-6 rounded-full object-cover flex-shrink-0">`
                : `<div class="w-6 h-6 rounded-full bg-gray-200 flex items-center justify-center text-gray-700 font-bold text-[10px] flex-shrink-0">${member.initials}</div>`

            return `
                <label class="flex items-center gap-2 px-3 py-2 hover:bg-gray-50 cursor-pointer" data-member-name="${member.name.toLowerCase()}">
                    <input type="checkbox" value="${member.key}" ${checked}
                           data-action="change->show-roles-modal#memberCheckboxChanged"
                           class="accent-pink-500 cursor-pointer">
                    ${avatar}
                    <span class="text-sm text-gray-700">${member.name}</span>
                </label>
            `
        }).join("")
    }

    memberCheckboxChanged(event) {
        const key = event.target.value
        if (event.target.checked) {
            if (!this.selectedMemberKeys.includes(key)) {
                this.selectedMemberKeys.push(key)
            }
        } else {
            this.selectedMemberKeys = this.selectedMemberKeys.filter(k => k !== key)
        }
    }

    filterMembers() {
        const query = this.memberSearchInputTarget.value.toLowerCase()
        const items = this.membersListTarget.querySelectorAll("[data-member-name]")

        items.forEach(item => {
            const name = item.dataset.memberName
            if (name.includes(query)) {
                item.classList.remove("hidden")
            } else {
                item.classList.add("hidden")
            }
        })
    }

    // Save role
    // Save role
    async saveRole() {
        const name = this.roleNameInputTarget.value.trim()

        if (!name) {
            this.showRoleNameError("Role name is required")
            return
        }

        const newQuantity = this.hasQuantityInputTarget ? parseInt(this.quantityInputTarget.value) || 1 : 1

        // If editing, check if we're reducing slots below the number of current assignments
        if (this.editingRoleId) {
            const currentRole = this.roles.find(r => r.id === this.editingRoleId)

            // Only show migration if we're reducing slots AND we have more assignments than new slots
            if (currentRole && currentRole.assignments_count > newQuantity) {
                // Fetch preview from server
                try {
                    const previewUrl = `${this.rolesUrlValue}/${this.editingRoleId}/slot_change_preview?new_quantity=${newQuantity}`
                    const response = await fetch(previewUrl, {
                        headers: {
                            "Accept": "application/json",
                            "X-CSRF-Token": this.csrfToken
                        }
                    })
                    const data = await response.json()

                    if (data.needs_decision) {
                        // Show slot change modal for user to choose who to remove
                        this.showSlotChangeModal(data, name)
                        return
                    }
                } catch (error) {
                    console.error("Failed to check slot change:", error)
                }
            }
        }

        // No migration needed, proceed with normal save
        await this.executeSaveRole(name, newQuantity)
    }

    // Execute the actual role save
    async executeSaveRole(name, quantity, keepAssignmentIds = null) {
        const url = this.editingRoleId
            ? `${this.rolesUrlValue}/${this.editingRoleId}`
            : this.rolesUrlValue

        const method = this.editingRoleId ? "PATCH" : "POST"

        // Build the role data
        const roleData = {
            name: name,
            restricted: this.restrictedCheckboxTarget.checked,
            eligible_member_ids: this.restrictedCheckboxTarget.checked ? this.selectedMemberKeys : []
        }

        // Add quantity and category
        roleData.quantity = quantity
        if (this.hasCategorySelectTarget) {
            roleData.category = this.categorySelectTarget.value
        }

        const body = { show_role: roleData }

        // If we have slot changes with assignments to keep, use the slot_change endpoint instead
        if (keepAssignmentIds !== null && this.editingRoleId) {
            try {
                const response = await fetch(`${this.rolesUrlValue}/${this.editingRoleId}/execute_slot_change`, {
                    method: "POST",
                    headers: {
                        "Accept": "application/json",
                        "Content-Type": "application/json",
                        "X-CSRF-Token": this.csrfToken
                    },
                    body: JSON.stringify({
                        new_quantity: quantity,
                        keep_assignment_ids: keepAssignmentIds
                    })
                })

                const data = await response.json()

                if (data.success) {
                    // Also update name and other fields if changed
                    const currentRoleData = this.roles.find(r => r.id === this.editingRoleId)
                    if (currentRoleData && (currentRoleData.name !== name || currentRoleData.category !== this.categorySelectTarget?.value)) {
                        // Do a follow-up update for other fields
                        await this.updateRoleFields(name)
                    } else {
                        const index = this.roles.findIndex(r => r.id === this.editingRoleId)
                        if (index !== -1) {
                            this.roles[index] = data.role
                        }
                    }
                    this.cancelSlotChange()
                    this.hideForm()
                } else {
                    const errorMsg = data.error || "Failed to save role"
                    this.showRoleNameError(errorMsg)
                }
            } catch (error) {
                console.error("Failed to execute slot change:", error)
                this.showRoleNameError("Failed to save role. Please try again.")
            }
            return
        }

        try {
            const response = await fetch(url, {
                method: method,
                headers: {
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                    "X-CSRF-Token": this.csrfToken
                },
                body: JSON.stringify(body)
            })

            const data = await response.json()

            if (data.success) {
                if (this.editingRoleId) {
                    const index = this.roles.findIndex(r => r.id === this.editingRoleId)
                    if (index !== -1) {
                        this.roles[index] = data.role
                    }
                } else {
                    this.roles.push(data.role)
                }
                this.hideForm()
            } else {
                const errorMsg = data.errors ? data.errors.join(", ") : "Failed to save role"
                this.showRoleNameError(errorMsg)
            }
        } catch (error) {
            console.error("Failed to save role:", error)
            this.showRoleNameError("Failed to save role. Please try again.")
        }
    }

    // Update just the name/category fields after a slot change
    async updateRoleFields(name) {
        const roleData = {
            name: name,
            restricted: this.restrictedCheckboxTarget.checked,
            eligible_member_ids: this.restrictedCheckboxTarget.checked ? this.selectedMemberKeys : []
        }
        if (this.hasCategorySelectTarget) {
            roleData.category = this.categorySelectTarget.value
        }

        try {
            const response = await fetch(`${this.rolesUrlValue}/${this.editingRoleId}`, {
                method: "PATCH",
                headers: {
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                    "X-CSRF-Token": this.csrfToken
                },
                body: JSON.stringify({ show_role: roleData })
            })

            const data = await response.json()
            if (data.success) {
                const index = this.roles.findIndex(r => r.id === this.editingRoleId)
                if (index !== -1) {
                    this.roles[index] = data.role
                }
            }
        } catch (error) {
            console.error("Failed to update role fields:", error)
        }
    }

    // Show modal for slot reduction requiring decision
    showSlotChangeModal(data, roleName) {
        if (!this.hasSlotChangeModalTarget) return

        this.slotChangeData = { ...data, pendingRoleName: roleName }
        this.selectedKeepAssignments = new Set()

        // Pre-select assignments up to the new quantity (first N by position)
        data.assignments.slice(0, data.new_quantity).forEach(a => {
            this.selectedKeepAssignments.add(a.assignment_id)
        })

        // Update title
        if (this.hasSlotChangeTitleTarget) {
            this.slotChangeTitleTarget.textContent = `Reducing ${data.role_name} slots`
        }

        // Update message
        if (this.hasSlotChangeMessageTarget) {
            this.slotChangeMessageTarget.innerHTML = `
                <p class="text-gray-700">
                    You're reducing this role from <strong>${data.current_assignment_count} assigned</strong> to <strong>${data.new_quantity} slots</strong>.
                </p>
                <p class="text-gray-600 mt-1">
                    Select which ${data.new_quantity} ${data.new_quantity === 1 ? 'person' : 'people'} to keep:
                </p>
            `
        }

        // Build assignment list with checkboxes
        if (this.hasSlotChangeListTarget) {
            this.slotChangeListTarget.innerHTML = data.assignments.map((a, index) => {
                const checked = index < data.new_quantity ? 'checked' : ''
                const avatar = a.headshot_url
                    ? `<img src="${a.headshot_url}" alt="${a.assignable_name}" class="w-10 h-10 rounded-lg object-cover flex-shrink-0">`
                    : `<div class="w-10 h-10 rounded-lg bg-gray-200 flex items-center justify-center text-gray-700 font-bold text-sm flex-shrink-0">${a.initials}</div>`

                return `
                    <label class="flex items-center gap-3 p-3 bg-gray-50 border border-gray-200 rounded-lg cursor-pointer hover:bg-gray-100 transition-colors">
                        <input type="checkbox" value="${a.assignment_id}" ${checked}
                               data-action="change->show-roles-modal#slotKeepCheckboxChanged"
                               class="w-5 h-5 accent-pink-500 cursor-pointer flex-shrink-0">
                        ${avatar}
                        <span class="font-medium text-gray-900">${a.assignable_name}</span>
                    </label>
                `
            }).join("")
        }

        this.updateSlotChangeStats()
        this.slotChangeModalTarget.classList.remove("hidden")
    }

    // Show modal for slot increase (just confirmation)
    showSlotIncreaseModal(data, roleName) {
        if (!this.hasSlotChangeModalTarget) return

        this.slotChangeData = { ...data, pendingRoleName: roleName, isIncrease: true }

        // Update title
        if (this.hasSlotChangeTitleTarget) {
            this.slotChangeTitleTarget.textContent = `Adding slots to ${data.role_name}`
        }

        // Update message
        if (this.hasSlotChangeMessageTarget) {
            this.slotChangeMessageTarget.innerHTML = `
                <p class="text-gray-700">
                    You're increasing this role from <strong>${data.current_quantity} slots</strong> to <strong>${data.new_quantity} slots</strong>.
                </p>
                <p class="text-gray-600 mt-1">
                    ${data.slots_being_added} new ${data.slots_being_added === 1 ? 'slot' : 'slots'} will be available for casting.
                </p>
            `
        }

        // Show current assignments
        if (this.hasSlotChangeListTarget) {
            if (data.assignments.length > 0) {
                this.slotChangeListTarget.innerHTML = `
                    <p class="text-sm text-gray-500 mb-2">Currently assigned:</p>
                    ${data.assignments.map(a => {
                    const avatar = a.headshot_url
                        ? `<img src="${a.headshot_url}" alt="${a.assignable_name}" class="w-8 h-8 rounded-lg object-cover flex-shrink-0">`
                        : `<div class="w-8 h-8 rounded-lg bg-gray-200 flex items-center justify-center text-gray-700 font-bold text-xs flex-shrink-0">${a.initials}</div>`
                    return `
                            <div class="flex items-center gap-2 p-2 bg-gray-50 border border-gray-200 rounded-lg">
                                ${avatar}
                                <span class="text-sm text-gray-700">${a.assignable_name}</span>
                            </div>
                        `
                }).join("")}
                `
            } else {
                this.slotChangeListTarget.innerHTML = ''
            }
        }

        // Update stats for increase
        if (this.hasSlotChangeStatsTarget) {
            this.slotChangeStatsTarget.textContent = `${data.current_assignment_count} assigned, adding ${data.slots_being_added} slots`
        }

        this.slotChangeModalTarget.classList.remove("hidden")
    }

    // Handle checkbox change in slot change modal
    slotKeepCheckboxChanged(event) {
        const assignmentId = parseInt(event.target.value)

        if (event.target.checked) {
            this.selectedKeepAssignments.add(assignmentId)
        } else {
            this.selectedKeepAssignments.delete(assignmentId)
        }

        this.updateSlotChangeStats()
    }

    // Update the stats in slot change modal
    updateSlotChangeStats() {
        if (!this.hasSlotChangeStatsTarget || !this.slotChangeData) return

        const keepCount = this.selectedKeepAssignments.size
        const removeCount = this.slotChangeData.current_assignment_count - keepCount
        const newQuantity = this.slotChangeData.new_quantity

        let message = `${keepCount} will be kept`
        if (removeCount > 0) {
            message += `, ${removeCount} will be removed`
        }

        // Validation message
        if (keepCount > newQuantity) {
            message = `⚠️ Select only ${newQuantity} (you have ${keepCount} selected)`
            if (this.hasSlotChangeExecuteButtonTarget) {
                this.slotChangeExecuteButtonTarget.disabled = true
            }
        } else if (keepCount < newQuantity && this.slotChangeData.current_assignment_count >= newQuantity) {
            message = `Select ${newQuantity - keepCount} more to fill all slots`
            if (this.hasSlotChangeExecuteButtonTarget) {
                this.slotChangeExecuteButtonTarget.disabled = false
            }
        } else {
            if (this.hasSlotChangeExecuteButtonTarget) {
                this.slotChangeExecuteButtonTarget.disabled = false
            }
        }

        this.slotChangeStatsTarget.textContent = message
    }

    // Execute the slot change
    async executeSlotChange() {
        if (!this.slotChangeData) return

        // Disable button
        if (this.hasSlotChangeExecuteButtonTarget) {
            this.slotChangeExecuteButtonTarget.disabled = true
            this.slotChangeExecuteButtonTarget.textContent = "Saving..."
        }

        const keepAssignmentIds = this.slotChangeData.isIncrease ? null : Array.from(this.selectedKeepAssignments)

        await this.executeSaveRole(
            this.slotChangeData.pendingRoleName,
            this.slotChangeData.new_quantity,
            keepAssignmentIds
        )

        // Reset button
        if (this.hasSlotChangeExecuteButtonTarget) {
            this.slotChangeExecuteButtonTarget.disabled = false
            this.slotChangeExecuteButtonTarget.textContent = "Confirm Changes"
        }
    }

    // Cancel slot change modal
    cancelSlotChange() {
        if (this.hasSlotChangeModalTarget) {
            this.slotChangeModalTarget.classList.add("hidden")
        }
        this.slotChangeData = null
        this.selectedKeepAssignments = new Set()
    }

    showRoleNameError(message) {
        this.roleNameErrorTarget.textContent = message
        this.roleNameErrorTarget.classList.remove("hidden")
        this.roleNameInputTarget.classList.add("border-red-500")
    }

    hideRoleNameError() {
        this.roleNameErrorTarget.classList.add("hidden")
        this.roleNameInputTarget.classList.remove("border-red-500")
    }

    // Delete role
    deleteRole(event) {
        const roleId = parseInt(event.currentTarget.dataset.roleId)
        const role = this.roles.find(r => r.id === roleId)

        if (!role) return

        this.pendingDeleteRoleId = roleId

        if (role.assignments_count > 0) {
            this.deleteConfirmMessageTarget.textContent =
                `This role has ${role.assignments_count} assignment${role.assignments_count > 1 ? 's' : ''}. Deleting it will remove those assignments. Are you sure?`
        } else {
            this.deleteConfirmMessageTarget.textContent = `Are you sure you want to delete "${role.name}"?`
        }

        this.deleteConfirmModalTarget.classList.remove("hidden")
    }

    cancelDelete() {
        this.deleteConfirmModalTarget.classList.add("hidden")
        this.pendingDeleteRoleId = null
    }

    async confirmDelete() {
        if (!this.pendingDeleteRoleId) return

        const roleId = this.pendingDeleteRoleId
        this.deleteConfirmModalTarget.classList.add("hidden")

        try {
            const response = await fetch(`${this.rolesUrlValue}/${roleId}?confirm_delete=true`, {
                method: "DELETE",
                headers: {
                    "Accept": "application/json",
                    "X-CSRF-Token": this.csrfToken
                }
            })

            const data = await response.json()

            if (data.success) {
                this.roles = this.roles.filter(r => r.id !== roleId)
                this.renderRoles()
            } else {
                alert(data.message || "Failed to delete role")
            }
        } catch (error) {
            console.error("Failed to delete role:", error)
            alert("Failed to delete role. Please try again.")
        } finally {
            this.pendingDeleteRoleId = null
        }
    }

    // Drag and drop reordering
    startDrag(event) {
        event.dataTransfer.effectAllowed = "move"
        event.dataTransfer.setData("text/plain", event.currentTarget.dataset.roleId)
        event.currentTarget.classList.add("opacity-50")
        this.draggedElement = event.currentTarget
    }

    endDrag(event) {
        event.currentTarget.classList.remove("opacity-50")
        this.draggedElement = null
        // Remove all drop indicators
        this.rolesListTarget.querySelectorAll("[data-role-id]").forEach(el => {
            el.style.borderTop = ""
            el.style.borderBottom = ""
        })
    }

    dragOver(event) {
        event.preventDefault()
        event.dataTransfer.dropEffect = "move"

        const target = event.currentTarget
        if (target === this.draggedElement) return

        // Remove indicators from all other elements
        this.rolesListTarget.querySelectorAll("[data-role-id]").forEach(el => {
            el.style.borderTop = ""
            el.style.borderBottom = ""
        })

        // Determine if dropping above or below based on mouse position
        const rect = target.getBoundingClientRect()
        const midpoint = rect.top + rect.height / 2

        if (event.clientY < midpoint) {
            target.style.borderTop = "3px solid #ec4899"
        } else {
            target.style.borderBottom = "3px solid #ec4899"
        }
    }

    dragLeave(event) {
        event.currentTarget.style.borderTop = ""
        event.currentTarget.style.borderBottom = ""
    }

    async drop(event) {
        event.preventDefault()

        // Remove all drop indicators
        this.rolesListTarget.querySelectorAll("[data-role-id]").forEach(el => {
            el.style.borderTop = ""
            el.style.borderBottom = ""
        })

        const draggedId = parseInt(event.dataTransfer.getData("text/plain"))
        const targetId = parseInt(event.currentTarget.dataset.roleId)

        if (draggedId === targetId) return

        // Determine if dropping above or below based on mouse position
        const rect = event.currentTarget.getBoundingClientRect()
        const midpoint = rect.top + rect.height / 2
        const dropAbove = event.clientY < midpoint

        // Reorder in local array
        const draggedIndex = this.roles.findIndex(r => r.id === draggedId)
        let targetIndex = this.roles.findIndex(r => r.id === targetId)

        const [draggedRole] = this.roles.splice(draggedIndex, 1)

        // Adjust target index if needed after removal
        if (draggedIndex < targetIndex) {
            targetIndex--
        }

        // Insert at the correct position
        if (dropAbove) {
            this.roles.splice(targetIndex, 0, draggedRole)
        } else {
            this.roles.splice(targetIndex + 1, 0, draggedRole)
        }

        this.renderRoles()

        // Save to server
        const roleIds = this.roles.map(r => r.id)

        try {
            await fetch(this.reorderUrlValue, {
                method: "POST",
                headers: {
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                    "X-CSRF-Token": this.csrfToken
                },
                body: JSON.stringify({ role_ids: roleIds })
            })
        } catch (error) {
            console.error("Failed to reorder roles:", error)
        }
    }

    // Helper methods
    showLoading() {
        this.loadingTarget.classList.remove("hidden")
        this.emptyStateTarget.classList.add("hidden")
        this.rolesListSectionTarget.classList.add("hidden")
    }

    hideLoading() {
        this.loadingTarget.classList.add("hidden")
    }

    get csrfToken() {
        return document.querySelector('meta[name="csrf-token"]')?.content || ""
    }
}
