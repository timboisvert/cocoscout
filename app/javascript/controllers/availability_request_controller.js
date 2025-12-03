import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "specificSection",
        "castDropdown",
        "viewDetailsButton",
        "showsSection",
        "needingUpdateCount",
        "needingUpdateCountDetails",
        "upToDateCountDetails",
        "needingUpdateList",
        "upToDateList",
        "specificPeopleList",
        "talentPoolSelect"
    ]

    static values = {
        availabilityData: Array,
        talentPoolData: Array,
        allShowIds: Array
    }

    connect() {
        // Listen to all radio button changes
        this.element.addEventListener('change', (e) => {
            if (e.target.name === 'recipient_type') {
                this.handleRecipientTypeChange(e.target.value)
            }
        })

        // Initial calculation for talent pool dropdown
        this.updateTalentPoolDropdown()
    }

    toggleShowSelection(event) {
        const value = event.target.value
        if (value === "specific") {
            this.showsSectionTarget.classList.remove("hidden")
        } else {
            this.showsSectionTarget.classList.add("hidden")
            // When switching back to "all", recalculate with all shows
            this.updateRecipients()
        }
    }

    // Get the currently selected show IDs based on radio selection
    getSelectedShowIds() {
        const selectionType = document.querySelector('input[name="show_selection_type"]:checked')?.value
        if (selectionType === "all") {
            return this.allShowIdsValue
        } else {
            const checkedShows = Array.from(document.querySelectorAll('input[name="show_ids[]"]:checked'))
            return checkedShows.map(cb => parseInt(cb.value, 10))
        }
    }

    // Calculate which people need updates vs are up to date for the selected shows
    calculateRecipientStatus(selectedShowIds) {
        if (selectedShowIds.length === 0) {
            // If no shows selected, everyone is "up to date" (nothing to update)
            return {
                needingUpdate: [],
                upToDate: this.availabilityDataValue
            }
        }

        const needingUpdate = []
        const upToDate = []

        for (const person of this.availabilityDataValue) {
            // A person needs update if they haven't submitted for at least one of the selected shows
            const hasSubmittedAll = selectedShowIds.every(showId =>
                person.submitted_show_ids.includes(showId)
            )

            if (hasSubmittedAll) {
                upToDate.push(person)
            } else {
                needingUpdate.push(person)
            }
        }

        return { needingUpdate, upToDate }
    }

    updateRecipients() {
        const selectedShowIds = this.getSelectedShowIds()
        const { needingUpdate, upToDate } = this.calculateRecipientStatus(selectedShowIds)

        // Update counts
        if (this.hasNeedingUpdateCountTarget) {
            this.needingUpdateCountTarget.textContent = needingUpdate.length
        }
        if (this.hasNeedingUpdateCountDetailsTarget) {
            this.needingUpdateCountDetailsTarget.textContent = needingUpdate.length
        }
        if (this.hasUpToDateCountDetailsTarget) {
            this.upToDateCountDetailsTarget.textContent = upToDate.length
        }

        // Update the "Needs Updates" list in the details panel
        if (this.hasNeedingUpdateListTarget) {
            if (needingUpdate.length > 0) {
                this.needingUpdateListTarget.innerHTML = needingUpdate
                    .map(m => {
                        return `<div class="text-gray-600 flex items-center gap-1">${this.escapeHtml(m.name)}</div>`
                    })
                    .join('')
            } else {
                this.needingUpdateListTarget.innerHTML = '<div class="text-gray-400 italic">None</div>'
            }
        }

        // Update the "Up to Date" list in the details panel
        if (this.hasUpToDateListTarget) {
            if (upToDate.length > 0) {
                this.upToDateListTarget.innerHTML = upToDate
                    .map(m => {
                        return `<div class="text-green-600 flex items-center gap-1"><span class="mr-1">✓</span>${this.escapeHtml(m.name)}</div>`
                    })
                    .join('')
            } else {
                this.upToDateListTarget.innerHTML = '<div class="text-gray-400 italic">None</div>'
            }
        }

        // Update the specific people selection list
        if (this.hasSpecificPeopleListTarget) {
            this.updateSpecificPeopleList(needingUpdate, upToDate)
        }

        // Update talent pool dropdown
        this.updateTalentPoolDropdown(needingUpdate)
    }

    updateSpecificPeopleList(needingUpdate, upToDate) {
        const talentPoolLookup = {}
        for (const tp of this.talentPoolDataValue) {
            talentPoolLookup[tp.id] = tp.name
        }

        let html = ''

        if (needingUpdate.length > 0) {
            html += '<div class="text-xs font-semibold text-gray-700 uppercase mb-2">Needs Update</div>'
            for (const member of needingUpdate) {
                const poolNames = member.talent_pool_ids
                    .map(id => talentPoolLookup[id])
                    .filter(Boolean)
                    .join(', ')
                const fieldName = member.type === 'Group' ? 'group_ids[]' : 'person_ids[]'
                html += `
                    <label class="flex items-center cursor-pointer" data-member-id="${member.id}" data-member-type="${member.type}">
                        <input type="checkbox" name="${fieldName}" value="${member.id}" class="mr-2 accent-pink-500 cursor-pointer">
                        <span class="text-sm flex items-center gap-1">${this.escapeHtml(member.name)} <span class="text-gray-500">- ${this.escapeHtml(poolNames)}</span></span>
                    </label>
                `
            }
        }

        if (upToDate.length > 0) {
            html += `<div class="text-xs font-semibold text-gray-700 uppercase mb-2 ${needingUpdate.length > 0 ? 'mt-4' : ''}">Up to Date</div>`
            for (const member of upToDate) {
                const poolNames = member.talent_pool_ids
                    .map(id => talentPoolLookup[id])
                    .filter(Boolean)
                    .join(', ')
                const fieldName = member.type === 'Group' ? 'group_ids[]' : 'person_ids[]'
                html += `
                    <div class="flex items-center opacity-50" data-member-id="${member.id}" data-member-type="${member.type}">
                        <input type="checkbox" name="${fieldName}" value="${member.id}" disabled class="mr-2 cursor-not-allowed">
                        <span class="text-sm flex items-center gap-1">${this.escapeHtml(member.name)} <span class="text-gray-500">- ${this.escapeHtml(poolNames)}</span></span>
                        <span class="ml-2 text-xs text-green-600">✓</span>
                    </div>
                `
            }
        }

        if (html === '') {
            html = '<div class="text-gray-400 italic">No cast members</div>'
        }

        this.specificPeopleListTarget.innerHTML = html
    }

    updateTalentPoolDropdown(needingUpdate = null) {
        if (!this.hasTalentPoolSelectTarget) return

        if (needingUpdate === null) {
            const selectedShowIds = this.getSelectedShowIds()
            const result = this.calculateRecipientStatus(selectedShowIds)
            needingUpdate = result.needingUpdate
        }

        const needingUpdateIds = new Set(needingUpdate.map(p => p.id))

        // Build options for each talent pool
        const options = this.talentPoolDataValue.map(tp => {
            // Count people in this talent pool who need updates
            const count = this.availabilityDataValue.filter(person =>
                person.talent_pool_ids.includes(tp.id) && needingUpdateIds.has(person.id)
            ).length

            return `<option value="${tp.id}">${this.escapeHtml(tp.name)} (${count} needing updates)</option>`
        }).join('')

        this.talentPoolSelectTarget.innerHTML = options
    }

    updateMessage(event) {
        // Get all checked show checkboxes
        const checkedShows = Array.from(document.querySelectorAll('input[name="show_ids[]"]:checked'))

        if (checkedShows.length === 0) return

        // Build the shows list for the message
        const showsList = checkedShows.map(checkbox => {
            const label = checkbox.parentElement
            // Get the event type badge text
            const eventType = label.querySelector('.inline-flex').textContent.trim()

            // Get the date/time span (the one with text-sm class)
            const dateSpan = label.querySelector('span.text-sm')

            // Get all text content and parse it
            const fullText = dateSpan.textContent.trim()

            // Split by " - " to separate date/time from secondary name
            const parts = fullText.split(' - ')
            const dateTimePart = parts[0].trim() // e.g., "Fri, Dec 19, 2025 at 9:00 PM"
            const secondaryName = parts.length > 1 ? parts[1].trim() : null

            // Split date and time by " at "
            const atIndex = dateTimePart.indexOf(' at ')
            if (atIndex === -1) {
                // Fallback if format is unexpected
                return `• ${eventType} on ${dateTimePart}`
            }

            const datePart = dateTimePart.substring(0, atIndex).trim()
            const timePart = dateTimePart.substring(atIndex + 4).trim()

            // Build the formatted string
            let formatted = `• ${eventType} on ${datePart} at ${timePart}`
            if (secondaryName) {
                formatted += ` (${secondaryName})`
            }
            return formatted
        }).join('\n')

        // Get the current message
        const messageTextarea = document.querySelector('textarea[name="message"]')
        const currentMessage = messageTextarea.value

        // Replace the shows list in the message (everything between "following upcoming" and "You can update")
        const beforeShows = currentMessage.substring(0, currentMessage.indexOf('shows & events:') + 'shows & events:'.length)
        const afterShows = currentMessage.substring(currentMessage.indexOf('\n\nYou can update'))

        messageTextarea.value = `${beforeShows}\n\n${showsList}${afterShows}`
    }

    handleRecipientTypeChange(value) {
        // Hide both sections by default
        this.specificSectionTarget.classList.add("hidden")
        if (this.hasCastDropdownTarget) {
            this.castDropdownTarget.classList.add("hidden")
        }

        // Hide the cast member status details when switching away from "all"
        const statusDiv = document.getElementById('cast-member-status')
        if (statusDiv && value !== "all") {
            statusDiv.classList.add("hidden")
        }

        // Show/hide the "View Details" button based on selection
        if (this.hasViewDetailsButtonTarget) {
            if (value === "all") {
                this.viewDetailsButtonTarget.classList.remove("hidden")
            } else {
                this.viewDetailsButtonTarget.classList.add("hidden")
            }
        }

        // Show the appropriate section based on selection
        if (value === "specific") {
            this.specificSectionTarget.classList.remove("hidden")
        } else if (value === "cast" && this.hasCastDropdownTarget) {
            this.castDropdownTarget.classList.remove("hidden")
        }
    }

    toggleSpecific(event) {
        this.handleRecipientTypeChange(event.target.value)
    }

    toggleCastDropdown(event) {
        this.handleRecipientTypeChange(event.target.value)
    }

    escapeHtml(text) {
        const div = document.createElement('div')
        div.textContent = text
        return div.innerHTML
    }
}
