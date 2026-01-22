import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["tabContainer", "panelContainer", "personBadge", "popup", "menu", "modal", "nameInput", "reviewCheckbox", "sendSection", "tabIndicator", "emailTemplate"]
    static values = {
        productionId: Number,
        auditionCycleId: Number,
        groupType: String  // 'casting' or 'audition'
    }

    connect() {
        // Close popup when clicking outside
        this.boundClosePopup = this.closePopup.bind(this)
        this.boundHandleEscape = this.handleEscape.bind(this)
        document.addEventListener("click", this.boundClosePopup)

        // Initialize activeGroupId based on URL hash or first visible tab
        this.initializeActiveGroup()
    }

    initializeActiveGroup() {
        // Check session storage first for preserved tab after reload
        const storedGroupId = sessionStorage.getItem('emailGroupsActiveTab')
        if (storedGroupId) {
            // Clear the stored value
            sessionStorage.removeItem('emailGroupsActiveTab')

            // Find the tab with this group ID
            const tabs = this.element.querySelectorAll('[data-group-tab]')
            const matchingTab = Array.from(tabs).find(tab => tab.dataset.groupId === storedGroupId)

            if (matchingTab) {
                this.activeGroupId = storedGroupId
                // Trigger tab selection to show correct panel
                matchingTab.click()
                return
            }
        }

        // Check URL hash to determine which tab should be active
        const hash = window.location.hash
        let tabIndex = 0

        if (hash && hash.startsWith('#tab-')) {
            tabIndex = parseInt(hash.replace('#tab-', ''), 10)
            if (isNaN(tabIndex) || tabIndex < 0) {
                tabIndex = 0
            }
        }

        // Find the tab at that index and set activeGroupId
        const tabs = this.element.querySelectorAll('[data-group-tab]')
        if (tabs[tabIndex]) {
            this.activeGroupId = tabs[tabIndex].dataset.groupId
        } else if (tabs[0]) {
            // Fallback to first tab
            this.activeGroupId = tabs[0].dataset.groupId
        }
    }

    disconnect() {
        document.removeEventListener("click", this.boundClosePopup)
        document.removeEventListener("keydown", this.boundHandleEscape)
    }

    handleEscape(event) {
        if (event.key === "Escape" || event.key === "Esc") {
            this.closeModal()
        }
    }

    createNewGroup(event) {
        event.preventDefault()
        this.showModal()
    }

    showModal() {
        // Create modal
        const modal = document.createElement("div")
        modal.className = "fixed inset-0 bg-black bg-opacity-50 z-50 flex items-center justify-center p-4"
        modal.dataset.emailGroupsTarget = "modal"

        const modalContent = document.createElement("div")
        modalContent.className = "bg-white rounded-lg shadow-lg w-full max-w-md"

        modalContent.innerHTML = `
            <div class="bg-white border-b border-gray-200 px-6 py-4 flex items-center justify-between">
                <h2 class="text-2xl font-semibold coustard-regular">Create New Email Group</h2>
                <button type="button" class="modal-close-btn text-gray-500 hover:text-gray-700">
                    <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                    </svg>
                </button>
            </div>
            <div class="px-6 py-6">
                <div class="mb-4">
                    <label class="block text-sm font-medium text-gray-700 mb-2">Group Name</label>
                    <input
                        type="text"
                        id="email-group-name-input"
                        maxlength="30"
                        placeholder="e.g., Callback Invites"
                        class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-pink-500"
                    />
                    <p class="text-xs text-gray-500 mt-1">Maximum 30 characters</p>
                </div>
                <div class="flex justify-end gap-2">
                    <button
                        type="button"
                        class="modal-cancel-btn px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50"
                    >
                        Cancel
                    </button>
                    <button
                        type="button"
                        class="modal-create-btn px-4 py-2 text-sm font-medium text-white bg-pink-500 border border-transparent rounded-lg hover:bg-pink-600"
                    >
                        Create
                    </button>
                </div>
            </div>
        `

        modal.appendChild(modalContent)
        document.body.appendChild(modal)

        // Add event listeners to the buttons
        const closeBtn = modal.querySelector(".modal-close-btn")
        const cancelBtn = modal.querySelector(".modal-cancel-btn")
        const createBtn = modal.querySelector(".modal-create-btn")
        const input = modal.querySelector("#email-group-name-input")

        closeBtn.addEventListener("click", (e) => {
            e.preventDefault()
            e.stopPropagation()
            this.closeModal()
        })

        cancelBtn.addEventListener("click", (e) => {
            e.preventDefault()
            e.stopPropagation()
            this.closeModal()
        })

        createBtn.addEventListener("click", (e) => {
            e.preventDefault()
            e.stopPropagation()
            this.saveNewGroup()
        })

        // Submit on Enter key in input
        input.addEventListener("keydown", (e) => {
            if (e.key === "Enter") {
                e.preventDefault()
                this.saveNewGroup()
            }
        })

        // Click outside to close
        modal.addEventListener("click", (e) => {
            if (e.target === modal) {
                this.closeModal()
            }
        })

        // Stop propagation on modal content
        modalContent.addEventListener("click", (e) => {
            e.stopPropagation()
        })

        // Add escape key listener
        document.addEventListener("keydown", this.boundHandleEscape)

        // Focus the input
        setTimeout(() => {
            if (input) input.focus()
        }, 100)
    }

    closeModal(event) {
        if (event) {
            event.preventDefault()
            event.stopPropagation()
        }
        const modal = document.querySelector('[data-email-groups-target="modal"]')
        if (modal) {
            modal.remove()
        }
        // Remove escape key listener
        document.removeEventListener("keydown", this.boundHandleEscape)
    }

    saveNewGroup() {
        const input = document.querySelector("#email-group-name-input")
        const groupName = input.value.trim()

        if (!groupName) {
            alert("Please enter a name for the email group")
            return
        }

        const newGroupId = `group_${Date.now()}`
        const groupType = this.groupTypeValue || 'casting'

        // Create the new group via AJAX
        fetch(`/manage/communications/${this.productionIdValue}/email_groups`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
            },
            body: JSON.stringify({
                email_group: {
                    group_id: newGroupId,
                    name: groupName,
                    group_type: groupType
                }
            })
        })
            .then(response => {
                if (response.ok) {
                    // Reload to show the new tab
                    window.location.reload()
                } else {
                    console.error("Failed to create email group")
                    alert("Failed to create email group")
                }
            })
            .catch(error => {
                console.error("Error:", error)
                alert("An error occurred")
            })

        this.closeModal()
    }

    showPopup(event) {
        event.stopPropagation()

        const badge = event.currentTarget
        const personId = badge.dataset.personId
        const emailAssignmentId = badge.dataset.emailAssignmentId
        const personCastId = badge.dataset.castId // The cast this person actually belongs to (empty string if not in a cast)

        // Close any existing popup
        this.closePopup()

        // Determine the group type (casting vs invitation)
        const groupType = this.groupTypeValue || 'casting'
        const isInvitationType = groupType === 'invitation'

        // Determine if this person is in a cast (for casting type)
        const isInCast = personCastId && personCastId !== ''

        // Determine if we're currently viewing a custom group tab
        const isCustomGroupActive = this.activeGroupId &&
            !this.activeGroupId.startsWith('default_') &&
            !this.activeGroupId.startsWith('invitation_') &&
            this.activeGroupId !== 'unassigned'

        // Get available groups from the page
        const availableGroups = []
        document.querySelectorAll('[data-group-tab]').forEach(tab => {
            const groupId = tab.dataset.groupId
            const groupName = tab.textContent.trim()
            const tabCastId = tab.dataset.castId

            // Skip the current active group and the "+ New Email Group" button
            if (groupId === this.activeGroupId || groupName.includes('+ New Email Group')) {
                return
            }

            // Determine if this tab is a custom group
            const isCustomGroup = !groupId.startsWith('default_') &&
                !groupId.startsWith('invitation_') &&
                groupId !== 'unassigned'

            if (isInvitationType) {
                // INVITATION TYPE LOGIC
                // From "Invited to Audition": can move to custom groups only
                // From "Not Invited": can move to custom groups only
                // From custom group: can move to other custom groups OR back to THEIR ORIGINAL group

                if (this.activeGroupId === 'invitation_accepted') {
                    // From "Invited to Audition" - can only move to custom groups
                    if (!isCustomGroup) {
                        return // Skip default invitation tabs
                    }
                } else if (this.activeGroupId === 'invitation_not_accepted') {
                    // From "Not Invited" - can only move to custom groups
                    if (!isCustomGroup) {
                        return // Skip default invitation tabs
                    }
                } else if (isCustomGroupActive) {
                    // From custom group - can move to other custom groups OR back to their original group only
                    const originalGroup = badge.dataset.originalGroup
                    if (!isCustomGroup && groupId !== originalGroup) {
                        return // Skip - not their original group
                    }
                }
            } else {
                // CASTING TYPE LOGIC
                // Apply filtering rules based on where we are and where the person belongs
                if (isCustomGroupActive) {
                    // From a custom group, can move to:
                    // 1. Other custom groups
                    // 2. Their actual cast's "Added to" tab (if in a cast)
                    // 3. "Not Being Added" tab (if not in a cast)

                    if (isCustomGroup) {
                        // Allow: other custom groups
                    } else if (groupId === 'unassigned' && !isInCast) {
                        // Allow: "Not Being Added" if person is not in a cast
                    } else if (groupId.startsWith('default_') && tabCastId === personCastId && isInCast) {
                        // Allow: their actual cast's default tab
                    } else {
                        return // Skip this option
                    }
                } else {
                    // From a default cast tab or "Not Being Added" tab, can move to:
                    // - Any custom group

                    if (!isCustomGroup) {
                        return // Skip default/unassigned tabs
                    }
                }
            }

            // Extract just the name without the count
            const nameMatch = groupName.match(/^(.+?)\s*\(\d+\)$/)
            const cleanName = nameMatch ? nameMatch[1] : groupName
            availableGroups.push({ id: groupId, name: cleanName, castId: tabCastId })
        })

        // Create popup menu
        const popup = document.createElement("div")
        popup.className = "absolute z-50 mt-1 bg-white border border-gray-300 rounded-lg shadow-lg py-1 min-w-[200px]"
        popup.dataset.emailGroupsTarget = "popup"

        // Add menu items for each email group
        availableGroups.forEach(group => {
            const item = document.createElement("button")
            item.type = "button"
            item.className = "w-full text-left px-4 py-2 text-sm hover:bg-gray-100 transition-colors cursor-pointer"
            item.textContent = `Move to ${group.name}`
            item.dataset.groupId = group.id
            item.dataset.castId = group.castId || ''
            item.dataset.personId = personId
            item.dataset.emailAssignmentId = emailAssignmentId

            // Manually attach click event listener
            item.addEventListener("click", (e) => this.moveToGroup(e))

            popup.appendChild(item)
        })

        // Position popup relative to badge
        const rect = badge.getBoundingClientRect()
        popup.style.position = "fixed"
        popup.style.top = `${rect.bottom + 4}px`
        popup.style.left = `${rect.left}px`

        document.body.appendChild(popup)
    }

    closePopup(event) {
        // Don't close if clicking inside a popup
        if (event && event.target.closest('[data-email-groups-target="popup"]')) {
            return
        }

        const existingPopups = document.querySelectorAll('[data-email-groups-target="popup"]')
        existingPopups.forEach(popup => popup.remove())
    }

    moveToGroup(event) {
        event.stopPropagation()

        const groupId = event.currentTarget.dataset.groupId
        const personId = event.currentTarget.dataset.personId
        const emailAssignmentId = event.currentTarget.dataset.emailAssignmentId

        // If moving to "unassigned" or a default group, delete the email assignment
        if (groupId === 'unassigned' || groupId.startsWith('default_')) {
            if (emailAssignmentId && emailAssignmentId !== '') {
                // Delete the email assignment to revert to default
                fetch(`/manage/communications/${this.productionIdValue}/audition_email_assignments/${emailAssignmentId}`, {
                    method: "DELETE",
                    headers: {
                        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
                    }
                })
                    .then(response => {
                        if (response.ok) {
                            // Preserve the current tab by storing it in session storage
                            sessionStorage.setItem('emailGroupsActiveTab', this.activeGroupId)
                            window.location.reload()
                        } else {
                            console.error("Failed to remove email assignment")
                            alert("Failed to move person")
                        }
                    })
            } else {
                // Already in default state, nothing to do
                sessionStorage.setItem('emailGroupsActiveTab', this.activeGroupId)
                window.location.reload()
            }
        }
        // If there's an existing email assignment, update it
        else if (emailAssignmentId && emailAssignmentId !== '') {
            fetch(`/manage/communications/${this.productionIdValue}/audition_email_assignments/${emailAssignmentId}`, {
                method: "PATCH",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
                },
                body: JSON.stringify({
                    audition_email_assignment: {
                        email_group_id: groupId
                    }
                })
            })
                .then(response => {
                    if (response.ok) {
                        // Preserve the current tab by storing it in session storage
                        sessionStorage.setItem('emailGroupsActiveTab', this.activeGroupId)
                        window.location.reload()
                    } else {
                        console.error("Failed to update email assignment")
                        alert("Failed to move person")
                    }
                })
        }
        // Otherwise, create a new email assignment
        else {
            fetch(`/manage/communications/${this.productionIdValue}/audition_email_assignments`, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
                },
                body: JSON.stringify({
                    audition_email_assignment: {
                        person_id: personId,
                        email_group_id: groupId
                    }
                })
            })
                .then(response => {
                    if (response.ok) {
                        // Preserve the current tab by storing it in session storage
                        sessionStorage.setItem('emailGroupsActiveTab', this.activeGroupId)
                        window.location.reload()
                    } else {
                        console.error("Failed to create email assignment")
                        alert("Failed to move person")
                    }
                })
        }

        this.closePopup()
    }

    selectGroup(event) {
        const groupId = event.currentTarget.dataset.groupId
        this.activeGroupId = groupId

        // Update tab styles
        this.element.querySelectorAll('[data-group-tab]').forEach(tab => {
            if (tab.dataset.groupId === groupId) {
                tab.classList.remove("text-gray-500", "bg-gray-50", "border-transparent")
                tab.classList.add("text-pink-600", "border-pink-600")
            } else {
                tab.classList.remove("text-pink-600", "border-pink-600")
                tab.classList.add("text-gray-500", "bg-gray-50", "border-transparent")
            }
        })

        // Update panel visibility
        this.element.querySelectorAll('[data-group-panel]').forEach(panel => {
            if (panel.dataset.groupId === groupId) {
                panel.classList.remove("hidden")
            } else {
                panel.classList.add("hidden")
            }
        })
    }

    checkAllReviewed() {
        // Update tab indicators for each checkbox
        this.reviewCheckboxTargets.forEach(checkbox => {
            const groupId = checkbox.dataset.checkboxGroupId
            const indicator = this.tabIndicatorTargets.find(ind => ind.dataset.tabGroupId === groupId)

            if (indicator) {
                if (checkbox.checked) {
                    indicator.classList.remove("hidden")

                    // Save the email template when checkbox is checked
                    this.saveEmailTemplate(groupId)
                } else {
                    indicator.classList.add("hidden")
                }
            }
        })

        // Check if all review checkboxes are checked
        const allChecked = this.reviewCheckboxTargets.every(checkbox => checkbox.checked)

        // Show or hide the send section based on whether all are checked
        if (this.hasSendSectionTarget) {
            if (allChecked && this.reviewCheckboxTargets.length > 0) {
                this.sendSectionTarget.classList.remove("hidden")
            } else {
                this.sendSectionTarget.classList.add("hidden")
            }
        }
    }

    sendNotifications(event) {
        const groupType = this.groupTypeValue || 'casting'
        const isInvitation = groupType === 'audition'

        const confirmMessage = isInvitation
            ? "Are you sure you want to send audition invitation emails to all applicants? This action cannot be undone."
            : "Are you sure you want to finalize cast changes and send notification emails to all auditionees? This action cannot be undone."

        if (!confirm(confirmMessage)) {
            return
        }

        // Disable the button to prevent double-clicks
        const button = event.target
        button.disabled = true
        button.textContent = "Sending..."

        const endpoint = isInvitation
            ? `/manage/signups/auditions/${this.productionIdValue}/${this.auditionCycleIdValue}/finalize_and_notify_invitations`
            : `/manage/signups/auditions/${this.productionIdValue}/${this.auditionCycleIdValue}/finalize_and_notify`

        // Create a form and submit it to trigger proper redirect with flash notice
        const form = document.createElement('form')
        form.method = 'POST'
        form.action = endpoint

        // Add CSRF token
        const csrfInput = document.createElement('input')
        csrfInput.type = 'hidden'
        csrfInput.name = 'authenticity_token'
        csrfInput.value = document.querySelector('meta[name="csrf-token"]').content
        form.appendChild(csrfInput)

        document.body.appendChild(form)
        form.submit()
    }

    deleteGroup(event) {
        event.stopPropagation()

        const groupId = event.currentTarget.dataset.groupId

        if (!confirm("Are you sure you want to delete this email group? This action cannot be undone.")) {
            return
        }

        fetch(`/manage/communications/${this.productionIdValue}/email_groups/${groupId}`, {
            method: "DELETE",
            headers: {
                "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
            }
        })
            .then(response => {
                if (response.ok) {
                    // Preserve the first tab as active after reload
                    sessionStorage.removeItem('emailGroupsActiveTab')
                    window.location.reload()
                } else {
                    console.error("Failed to delete email group")
                    alert("Failed to delete email group")
                }
            })
            .catch(error => {
                console.error("Error:", error)
                alert("An error occurred while deleting the group")
            })
    }

    saveEmailTemplate(groupId) {
        // Find the textarea for this group
        const textarea = this.emailTemplateTargets.find(ta => ta.dataset.groupId === groupId)
        if (!textarea) {
            return
        }

        const emailTemplate = textarea.value
        const emailGroupId = textarea.dataset.emailGroupId

        // If there's no existing EmailGroup record, create one first
        if (!emailGroupId) {
            // Determine the name based on group type and group_id
            let groupName
            if (this.groupTypeValue === 'audition') {
                groupName = groupId === 'invitation_accepted' ? 'Invited to Audition' : 'Not Invited'
            } else if (this.groupTypeValue === 'casting') {
                if (groupId === 'unassigned') {
                    groupName = 'Not Being Added'
                } else if (groupId.startsWith('default_')) {
                    // For default cast groups, get the cast name from the DOM
                    const castTab = this.element.querySelector(`[data-group-id="${groupId}"]`)
                    if (castTab) {
                        // Extract cast name from the tab text (e.g., "Added to Main Cast (1)")
                        const tabText = castTab.textContent.trim()
                        const match = tabText.match(/Added to (.+?) \(\d+\)/)
                        groupName = match ? `Added to ${match[1]}` : 'Added to Cast'
                    } else {
                        groupName = 'Added to Cast'
                    }
                } else {
                    groupName = groupId
                }
            } else {
                groupName = groupId
            }

            // Create a new EmailGroup with this group_id and email_template
            fetch(`/manage/communications/${this.productionIdValue}/email_groups`, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
                },
                body: JSON.stringify({
                    email_group: {
                        group_id: groupId,
                        group_type: this.groupTypeValue,
                        name: groupName,
                        email_template: emailTemplate
                    }
                })
            })
                .then(response => response.json())
                .then(data => {
                    if (data.id) {
                        // Store the new email_group_id on the textarea
                        textarea.dataset.emailGroupId = data.id
                    }
                })
                .catch(error => {
                    console.error("Error creating email group:", error)
                })
        } else {
            // Update existing EmailGroup
            fetch(`/manage/communications/${this.productionIdValue}/email_groups/${emailGroupId}`, {
                method: "PATCH",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
                },
                body: JSON.stringify({
                    email_group: {
                        email_template: emailTemplate
                    }
                })
            })
                .catch(error => {
                    console.error("Error updating email template:", error)
                })
        }
    }
}
