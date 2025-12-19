import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["list", "modal", "searchInput", "results", "loading"]

    connect() {
        this.searchTimeout = null
    }

    openSearchModal(event) {
        event.preventDefault()
        this.modalTarget.classList.remove('hidden')
        this.searchInputTarget.value = ''
        this.resultsTarget.innerHTML = '<p class="text-sm text-gray-500 text-center py-4">Search for groups to join</p>'
    }

    closeModal(event) {
        if (event) event.preventDefault()
        this.modalTarget.classList.add('hidden')
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    search(event) {
        const query = event.target.value.trim()

        clearTimeout(this.searchTimeout)

        if (query.length < 2) {
            this.resultsTarget.innerHTML = '<p class="text-sm text-gray-500 text-center py-4">Enter at least 2 characters to search</p>'
            return
        }

        this.searchTimeout = setTimeout(() => {
            this.performSearch(query)
        }, 300)
    }

    async performSearch(query) {
        this.loadingTarget.classList.remove('hidden')
        this.resultsTarget.innerHTML = ''

        try {
            const response = await fetch(`/profile/search_groups?q=${encodeURIComponent(query)}`, {
                headers: {
                    'Accept': 'application/json'
                }
            })

            if (!response.ok) throw new Error('Search failed')

            const data = await response.json()
            this.displayResults(data.groups)
        } catch (error) {
            console.error('Search error:', error)
            this.resultsTarget.innerHTML = '<p class="text-sm text-red-500 text-center py-4">Search failed. Please try again.</p>'
        } finally {
            this.loadingTarget.classList.add('hidden')
        }
    }

    displayResults(groups) {
        if (groups.length === 0) {
            this.resultsTarget.innerHTML = '<p class="text-sm text-gray-500 text-center py-4">No groups found</p>'
            return
        }

        this.resultsTarget.innerHTML = groups.map(group => `
            <div class="flex items-center justify-between p-3 border border-gray-200 rounded-lg hover:border-pink-300 hover:bg-pink-50 transition-all">
                <div class="flex items-center gap-3 flex-1 min-w-0">
                    ${group.headshot_url ?
                `<img src="${group.headshot_url}" class="w-12 h-12 rounded-lg object-cover flex-shrink-0" />` :
                `<div class="w-12 h-12 rounded-lg bg-gradient-to-br from-pink-400 to-purple-500 flex items-center justify-center text-white font-bold flex-shrink-0">${group.initials}</div>`
            }
                    <div class="flex-1 min-w-0">
                        <div class="text-sm font-medium text-gray-900 truncate">${group.name}</div>
                        <div class="text-xs text-gray-500">${group.member_count} ${group.member_count === 1 ? 'member' : 'members'}</div>
                    </div>
                </div>
                <button type="button"
                        class="px-3 py-1.5 bg-pink-500 hover:bg-pink-600 text-white text-xs font-medium rounded-lg transition-colors cursor-pointer"
                        data-action="click->profile-groups#joinGroup"
                        data-group-id="${group.id}">
                    Join
                </button>
            </div>
        `).join('')
    }

    async joinGroup(event) {
        event.preventDefault()
        const button = event.currentTarget
        const groupId = button.dataset.groupId
        const originalText = button.textContent

        button.disabled = true
        button.textContent = 'Joining...'

        try {
            const response = await fetch('/profile/join_group', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
                },
                body: JSON.stringify({ group_id: groupId })
            })

            if (!response.ok) {
                const data = await response.json()
                throw new Error(data.error || 'Failed to join group')
            }

            const data = await response.json()

            // Refresh the page to show the new membership
            window.location.reload()
        } catch (error) {
            console.error('Join group error:', error)
            alert(error.message || 'Failed to join group. Please try again.')
            button.disabled = false
            button.textContent = originalText
        }
    }

    async removeGroup(event) {
        event.preventDefault()
        const membershipId = event.currentTarget.dataset.membershipId

        if (!confirm('Are you sure you want to leave this group?')) {
            return
        }

        try {
            const response = await fetch(`/profile/leave_group/${membershipId}`, {
                method: 'DELETE',
                headers: {
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
                }
            })

            if (!response.ok) {
                const data = await response.json()
                throw new Error(data.error || 'Failed to leave group')
            }

            // Remove the membership element from the DOM
            const membershipElement = document.querySelector(`[data-membership-id="${membershipId}"]`)
            if (membershipElement) {
                membershipElement.remove()
            }

            // Check if list is empty and show message
            const list = this.listTarget
            if (list.children.length === 0) {
                list.innerHTML = '<p class="text-sm text-gray-500 italic py-4 text-center">You\'re not part of any groups yet</p>'
            }
        } catch (error) {
            console.error('Leave group error:', error)
            alert(error.message || 'Failed to leave group. Please try again.')
        }
    }

    async toggleVisibility(event) {
        const checkbox = event.currentTarget
        const membershipId = checkbox.dataset.membershipId
        const showOnProfile = checkbox.checked

        try {
            const response = await fetch('/profile/toggle_group_visibility', {
                method: 'PATCH',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
                },
                body: JSON.stringify({
                    membership_id: membershipId,
                    show_on_profile: showOnProfile
                })
            })

            if (!response.ok) {
                const data = await response.json()
                throw new Error(data.error || 'Failed to update visibility')
            }
        } catch (error) {
            console.error('Toggle visibility error:', error)
            // Revert checkbox state
            checkbox.checked = !showOnProfile
            alert(error.message || 'Failed to update visibility. Please try again.')
        }
    }
}
