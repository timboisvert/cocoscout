import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["filterButton", "member", "list", "searchInput", "searchResults", "addGuestSection", "guestName", "guestEmail", "filterBar"]

    connect() {
        // Apply initial filter based on first active button
        const activeButton = this.filterButtonTargets.find(btn =>
            btn.classList.contains('bg-pink-500')
        )
        if (activeButton) {
            this.currentFilter = activeButton.dataset.filter
        } else {
            this.currentFilter = "all"
        }
        this.searchTimeout = null
        this.isSearching = false
    }

    filter(event) {
        event.preventDefault()
        const button = event.currentTarget
        const filterValue = button.dataset.filter

        this.currentFilter = filterValue

        // Update button styles
        this.filterButtonTargets.forEach(btn => {
            if (btn === button) {
                btn.classList.remove('bg-white', 'text-gray-700', 'border-gray-200')
                btn.classList.add('bg-pink-500', 'text-white', 'border-pink-500')
            } else {
                btn.classList.remove('bg-pink-500', 'text-white', 'border-pink-500')
                btn.classList.add('bg-white', 'text-gray-700', 'border-gray-200')
            }
        })

        // Apply filter to members
        this.applyFilter()
    }

    applyFilter() {
        this.memberTargets.forEach(member => {
            let shouldShow = true

            switch (this.currentFilter) {
                case "available":
                    shouldShow = member.dataset.isAvailable === 'true'
                    break
                case "fully-available":
                    shouldShow = member.dataset.isFullyAvailable === 'true'
                    break
                case "partially-available":
                    shouldShow = member.dataset.isPartiallyAvailable === 'true'
                    break
                case "unavailable":
                    shouldShow = member.dataset.availabilityStatus === 'unavailable'
                    break
                case "all":
                default:
                    shouldShow = true
                    break
            }

            member.style.display = shouldShow ? '' : 'none'
        })
    }

    search() {
        const query = this.hasSearchInputTarget ? this.searchInputTarget.value.trim() : ""

        if (this.searchTimeout) clearTimeout(this.searchTimeout)

        if (query.length === 0) {
            // Clear search, show pool members
            this.exitSearch()
            return
        }

        if (query.length < 2) return

        this.searchTimeout = setTimeout(() => this.performSearch(query), 250)
    }

    exitSearch() {
        this.isSearching = false
        if (this.hasListTarget) this.listTarget.classList.remove('hidden')
        if (this.hasFilterBarTarget) this.filterBarTarget.classList.remove('hidden')
        if (this.hasSearchResultsTarget) {
            this.searchResultsTarget.classList.add('hidden')
            this.searchResultsTarget.innerHTML = ''
        }
        if (this.hasAddGuestSectionTarget) this.addGuestSectionTarget.classList.add('hidden')
        this.applyFilter()
    }

    async performSearch(query) {
        // Get production ID from the parent drop-role controller
        const dropRoleEl = this.element.closest('[data-controller*="drop-role"]') ||
            document.querySelector('[data-drop-role-production-id-value]')
        const productionId = dropRoleEl?.dataset.dropRoleProductionIdValue
        if (!productionId) return

        this.isSearching = true

        // Hide pool list and filter bar, show search results
        if (this.hasListTarget) this.listTarget.classList.add('hidden')
        if (this.hasFilterBarTarget) this.filterBarTarget.classList.add('hidden')
        if (this.hasSearchResultsTarget) this.searchResultsTarget.classList.remove('hidden')

        try {
            const response = await fetch(`/manage/casting/${productionId}/search_people?q=${encodeURIComponent(query)}&include_availability=true&show_id=${this.getShowId()}`, {
                headers: {
                    "Accept": "application/json",
                    "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
                }
            })
            const data = await response.json()
            this.renderSearchResults(data.people || [], data.groups || [], query)
        } catch (error) {
            console.error('Mobile search error:', error)
            if (this.hasSearchResultsTarget) {
                this.searchResultsTarget.innerHTML = '<p class="text-sm text-red-500 text-center py-4">Error searching. Please try again.</p>'
            }
        }
    }

    getShowId() {
        const dropRoleEl = this.element.closest('[data-controller*="drop-role"]') ||
            document.querySelector('[data-drop-role-show-id-value]')
        return dropRoleEl?.dataset.dropRoleShowIdValue || ''
    }

    renderSearchResults(people, groups, query) {
        if (!this.hasSearchResultsTarget) return

        // Separate talent pool members (they come first with is_talent_pool flag)
        const poolPeople = people.filter(p => p.is_talent_pool)
        const otherPeople = people.filter(p => !p.is_talent_pool)

        let html = ''

        if (poolPeople.length > 0) {
            html += '<p class="text-xs font-medium text-gray-400 uppercase tracking-wide mb-2">Talent Pool</p>'
            poolPeople.forEach(person => { html += this.renderSearchResult(person) })
        }

        if (otherPeople.length > 0) {
            if (poolPeople.length > 0) html += '<div class="border-t border-gray-200 my-2 pt-2"><p class="text-xs font-medium text-gray-400 uppercase tracking-wide mb-2">Other People</p></div>'
            otherPeople.forEach(person => { html += this.renderSearchResult(person) })
        }

        if (groups.length > 0) {
            if (people.length > 0) html += '<div class="border-t border-gray-200 my-2 pt-2"><p class="text-xs font-medium text-gray-400 uppercase tracking-wide mb-2">Groups</p></div>'
            groups.forEach(group => { html += this.renderGroupResult(group) })
        }

        if (people.length === 0 && groups.length === 0) {
            html = '<p class="text-sm text-gray-400 text-center py-4">No results found</p>'
        }

        this.searchResultsTarget.innerHTML = html

        // Show add guest section
        if (this.hasAddGuestSectionTarget) {
            this.addGuestSectionTarget.classList.remove('hidden')
            // Pre-fill guest name with query if it looks like a name (not an email)
            if (this.hasGuestNameTarget && !query.includes('@')) {
                this.guestNameTarget.value = query
            }
        }
    }

    renderSearchResult(person) {
        const headshot = person.headshot_url
            ? `<img src="${person.headshot_url}" alt="${person.name}" class="w-10 h-10 rounded-lg object-cover flex-shrink-0">`
            : `<div class="w-10 h-10 rounded-lg bg-gray-200 flex items-center justify-center text-gray-700 font-bold text-xs flex-shrink-0">${person.initials || ''}</div>`

        let subtitle = ''
        if (person.availability_status === 'available') {
            subtitle = '<span class="text-green-600">Available</span>'
        } else if (person.availability_status === 'unavailable') {
            subtitle = '<span class="text-red-600">Unavailable</span>'
        }

        return `
            <button type="button"
                class="w-full flex items-center gap-3 p-3 rounded-lg hover:bg-pink-50 active:bg-pink-100 transition-all cursor-pointer text-left"
                data-action="click->drop-role#assignFromModal"
                data-assignable-type="Person"
                data-assignable-id="${person.id}">
                ${headshot}
                <div class="flex-1 min-w-0">
                    <div class="font-medium text-sm text-gray-900 truncate">${person.name}</div>
                    ${subtitle ? `<div class="text-xs">${subtitle}</div>` : ''}
                </div>
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5 text-gray-400">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
                </svg>
            </button>
        `
    }

    renderGroupResult(group) {
        const headshot = group.headshot_url
            ? `<img src="${group.headshot_url}" alt="${group.name}" class="w-10 h-10 rounded-lg object-cover flex-shrink-0">`
            : `<div class="w-10 h-10 rounded-lg bg-purple-100 flex items-center justify-center text-purple-700 font-bold text-xs flex-shrink-0">${group.initials || ''}</div>`

        return `
            <button type="button"
                class="w-full flex items-center gap-3 p-3 rounded-lg hover:bg-pink-50 active:bg-pink-100 transition-all cursor-pointer text-left"
                data-action="click->drop-role#assignFromModal"
                data-assignable-type="Group"
                data-assignable-id="${group.id}">
                ${headshot}
                <div class="flex-1 min-w-0">
                    <div class="font-medium text-sm text-gray-900 truncate">${group.name}</div>
                    <div class="text-xs text-purple-600">Group</div>
                </div>
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5 text-gray-400">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
                </svg>
            </button>
        `
    }

    addGuest() {
        const name = this.hasGuestNameTarget ? this.guestNameTarget.value.trim() : ''
        const email = this.hasGuestEmailTarget ? this.guestEmailTarget.value.trim() : ''

        if (!name) {
            alert('Please enter a name')
            return
        }

        // Find the drop-role controller and use its guest assignment flow
        const dropRoleEl = this.element.closest('[data-controller*="drop-role"]') ||
            document.querySelector('[data-controller*="drop-role"]')
        if (!dropRoleEl) return

        const dropRoleController = this.application.getControllerForElementAndIdentifier(dropRoleEl, 'drop-role')
        if (dropRoleController && dropRoleController.addGuestDirect) {
            dropRoleController.addGuestDirect(name, email)
        }
    }
}
