import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "modal", "loading", "emptyState", "rolesListSection", "rolesList",
        "roleForm", "formTitle", "roleNameInput", "roleNameError",
        "restrictedCheckbox", "eligibleMembersSection", "memberSearchInput", "membersList",
        "saveButtonText", "modalFooter", "customRolesCheckbox", "customRolesContent",
        "deleteConfirmModal", "deleteConfirmMessage", "inlineRolesList", "manageButton",
        "toggleConfirmModal", "toggleConfirmMessage", "toggleConfirmList",
        "quantityInput", "categorySelect"
    ]

    static values = {
        showId: Number,
        productionId: Number,
        rolesUrl: String,
        copyUrl: String,
        reorderUrl: String,
        talentPoolUrl: String,
        checkAssignmentsUrl: String,
        clearAssignmentsUrl: String
    }

    connect() {
        this.editingRoleId = null
        this.roles = []
        this.talentPoolMembers = []
        this.selectedMemberKeys = []
        this.pendingDeleteRoleId = null

        this.boundHandleKeydown = this.handleKeydown.bind(this)
        document.addEventListener("keydown", this.boundHandleKeydown)
    }

    disconnect() {
        document.removeEventListener("keydown", this.boundHandleKeydown)
    }

    handleKeydown(event) {
        if (event.key === "Escape") {
            if (this.hasToggleConfirmModalTarget && !this.toggleConfirmModalTarget.classList.contains("hidden")) {
                this.cancelToggle()
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

        // Check if there are existing assignments that would be cleared
        if (this.hasCheckAssignmentsUrlValue) {
            try {
                const response = await fetch(`${this.checkAssignmentsUrlValue}?switching_to=${enabled ? 'custom' : 'production'}`, {
                    headers: {
                        "Accept": "application/json",
                        "X-CSRF-Token": this.csrfToken
                    }
                })
                const data = await response.json()

                // Show modal if there are assignments OR if this is a linked show (affects other shows)
                if (data.has_assignments || (data.is_linked && data.linked_shows.length > 0)) {
                    // Store the intended state for after confirmation
                    this.pendingToggleTo = enabled

                    // Show the confirmation modal
                    this.showToggleConfirmModal(data)

                    // Revert checkbox to previous state until confirmed
                    this.customRolesCheckboxTarget.checked = !enabled
                    return
                }
            } catch (error) {
                console.error("Failed to check assignments:", error)
            }
        }

        // No assignments, just toggle the visibility
        this.applyToggleState(enabled)
    }

    // Apply the toggle state (show/hide custom roles content)
    applyToggleState(enabled) {
        if (enabled) {
            this.customRolesContentTarget.classList.remove("hidden")
        } else {
            this.customRolesContentTarget.classList.add("hidden")
        }
    }

    // Show the toggle confirmation modal
    showToggleConfirmModal(data) {
        if (!this.hasToggleConfirmModalTarget) return

        // Set the message
        const direction = data.switching_to === 'custom' ? 'custom roles' : 'production roles'
        let message = ''

        if (data.assignments.length > 0) {
            message = `Switching to ${direction} will clear ${data.assignments.length} existing role assignment(s). This cannot be undone.`

            // Add linked shows warning if applicable
            if (data.is_linked && data.linked_shows.length > 0) {
                message += ` This will also affect the following linked events:`
            }
        } else if (data.is_linked && data.linked_shows.length > 0) {
            // No assignments but there are linked shows
            message = `Switching to ${direction} will affect the following linked events:`
        }

        this.toggleConfirmMessageTarget.textContent = message

        // Build the assignment list with headshots
        let listHtml = data.assignments.map(a => {
            const avatar = a.headshot_url
                ? `<img src="${a.headshot_url}" alt="${a.assignable_name}" class="w-8 h-8 rounded-lg object-cover flex-shrink-0">`
                : `<div class="w-8 h-8 rounded-lg bg-gray-200 flex items-center justify-center text-gray-700 font-bold text-xs flex-shrink-0">${a.initials}</div>`
            return `<li class="py-2 flex items-center gap-3">${avatar}<span>${a.assignable_name} as <span class="font-medium">${a.role_name}</span></span></li>`
        }).join("")

        // Add linked shows section if applicable
        if (data.is_linked && data.linked_shows.length > 0) {
            const separator = data.assignments.length > 0 ? `<li class="pt-4 mt-4 border-t border-gray-200">` : `<li>`
            listHtml += `${separator}
                <div class="font-medium text-gray-900 mb-2">Linked Events That Will Be Affected:</div>
                <ul class="space-y-1 text-sm text-gray-700">
                    ${data.linked_shows.map(show => `<li>• ${show.title} (${show.event_date})</li>`).join("")}
                </ul>
            </li>`
        }

        this.toggleConfirmListTarget.innerHTML = listHtml

        this.toggleConfirmModalTarget.classList.remove("hidden")
    }

    // Confirm the toggle
    async confirmToggle() {
        if (!this.hasClearAssignmentsUrlValue) return

        try {
            const response = await fetch(this.clearAssignmentsUrlValue, {
                method: "POST",
                headers: {
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                    "X-CSRF-Token": this.csrfToken
                },
                body: JSON.stringify({ switching_to: this.pendingToggleTo ? 'custom' : 'production' })
            })

            if (response.ok) {
                // Update the checkbox and content visibility
                this.customRolesCheckboxTarget.checked = this.pendingToggleTo
                this.applyToggleState(this.pendingToggleTo)
            }
        } catch (error) {
            console.error("Failed to clear assignments:", error)
        } finally {
            this.cancelToggle()
        }
    }

    // Cancel the toggle
    cancelToggle() {
        if (this.hasToggleConfirmModalTarget) {
            this.toggleConfirmModalTarget.classList.add("hidden")
        }
        this.pendingToggleTo = null
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
                const restrictedIcon = role.restricted
                    ? `<svg class="ml-1 w-3.5 h-3.5 text-pink-500" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                         <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25Z" />
                       </svg>`
                    : ""
                return `<span class="inline-flex items-center px-3 py-1 rounded text-sm font-medium bg-gray-100 text-gray-800">${role.name}${restrictedIcon}</span>`
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
    async saveRole() {
        const name = this.roleNameInputTarget.value.trim()

        if (!name) {
            this.showRoleNameError("Role name is required")
            return
        }

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
        if (this.hasQuantityInputTarget) {
            roleData.quantity = parseInt(this.quantityInputTarget.value) || 1
        }
        if (this.hasCategorySelectTarget) {
            roleData.category = this.categorySelectTarget.value
        }

        const body = { show_role: roleData }

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
