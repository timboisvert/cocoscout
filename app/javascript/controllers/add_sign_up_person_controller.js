import { Controller } from "@hotwired/stimulus"

// Controller for adding a person to a sign-up slot or queue
export default class extends Controller {
    static targets = [
        "modal",
        "searchInput",
        "searchResults",
        "searchSpinner",
        "slotId",
        "instanceId",
        "slotName",
        "modalTitle"
    ]

    static values = {
        searchUrl: String,
        registerUrl: String,
        registerQueueUrl: String
    }

    connect() {
        this.debounceTimer = null
        this.isQueueMode = false
    }

    // Open the modal for a specific slot
    open(event) {
        event.preventDefault()
        event.stopPropagation()

        const button = event.currentTarget
        const slotId = button.dataset.slotId
        const slotName = button.dataset.slotName || `Slot ${slotId}`

        this.isQueueMode = false

        // Store slot info
        this.slotIdTarget.value = slotId
        if (this.hasSlotNameTarget) {
            this.slotNameTarget.textContent = slotName
        }
        if (this.hasModalTitleTarget) {
            this.modalTitleTarget.textContent = `Add to ${slotName}`
        }

        this.showModal()
    }

    // Open the modal for adding to queue
    openQueue(event) {
        event.preventDefault()
        event.stopPropagation()

        const button = event.currentTarget
        const instanceId = button.dataset.instanceId

        this.isQueueMode = true

        // Store instance info
        if (this.hasInstanceIdTarget) {
            this.instanceIdTarget.value = instanceId
        }
        if (this.hasSlotIdTarget) {
            this.slotIdTarget.value = ''
        }
        if (this.hasSlotNameTarget) {
            this.slotNameTarget.textContent = 'Queue'
        }
        if (this.hasModalTitleTarget) {
            this.modalTitleTarget.textContent = 'Add to Queue'
        }

        this.showModal()
    }

    showModal() {
        // Clear previous search
        this.searchInputTarget.value = ''
        this.searchResultsTarget.innerHTML = '<p class="text-sm text-gray-400 text-center py-4">Type to search...</p>'

        // Show modal
        this.modalTarget.classList.remove('hidden')
        document.body.classList.add('overflow-hidden')

        // Focus on search input
        setTimeout(() => {
            this.searchInputTarget.focus()
        }, 100)
    }

    // Close the modal
    close() {
        this.modalTarget.classList.add('hidden')
        document.body.classList.remove('overflow-hidden')
    }

    // Prevent closing when clicking inside the modal content
    stopPropagation(event) {
        event.stopPropagation()
    }

    // Search for people
    search() {
        const query = this.searchInputTarget.value.trim()

        if (query.length < 2) {
            this.searchResultsTarget.innerHTML = '<p class="text-sm text-gray-400 text-center py-4">Type to search...</p>'
            return
        }

        // Debounce
        clearTimeout(this.debounceTimer)
        this.debounceTimer = setTimeout(() => {
            this.performSearch(query)
        }, 300)
    }

    async performSearch(query) {
        if (!this.searchUrlValue) return

        // Show spinner
        if (this.hasSearchSpinnerTarget) {
            this.searchSpinnerTarget.classList.remove('hidden')
        }

        try {
            const url = new URL(this.searchUrlValue, window.location.origin)
            url.searchParams.set('q', query)

            const response = await fetch(url, {
                headers: {
                    'Accept': 'application/json',
                    'X-Requested-With': 'XMLHttpRequest'
                }
            })

            if (!response.ok) throw new Error('Search failed')

            const data = await response.json()
            this.renderResults(data.people || [])
        } catch (error) {
            console.error('Search error:', error)
            this.searchResultsTarget.innerHTML = '<p class="text-sm text-red-500 text-center py-4">Search failed. Please try again.</p>'
        } finally {
            if (this.hasSearchSpinnerTarget) {
                this.searchSpinnerTarget.classList.add('hidden')
            }
        }
    }

    renderResults(people) {
        if (people.length === 0) {
            this.searchResultsTarget.innerHTML = '<p class="text-sm text-gray-400 text-center py-4">No results found</p>'
            return
        }

        const html = people.map(person => `
            <button type="button"
                    class="w-full flex items-center gap-3 p-2 rounded-lg hover:bg-gray-100 text-left transition-colors cursor-pointer"
                    data-action="click->add-sign-up-person#selectPerson"
                    data-person-id="${person.id}"
                    data-person-name="${this.escapeHtml(person.name)}">
                ${person.headshot_url
                ? `<img src="${person.headshot_url}" class="w-8 h-8 rounded-lg object-cover" alt="">`
                : `<div class="w-8 h-8 rounded-lg bg-gray-200 flex items-center justify-center text-gray-500 text-sm font-medium">${person.initials}</div>`
            }
                <div class="flex-1 min-w-0">
                    <div class="text-sm font-medium text-gray-900 truncate">${this.escapeHtml(person.name)}</div>
                    ${person.email ? `<div class="text-xs text-gray-500 truncate">${this.escapeHtml(person.email)}</div>` : ''}
                </div>
            </button>
        `).join('')

        this.searchResultsTarget.innerHTML = html
    }

    // Select a person and submit the form
    async selectPerson(event) {
        event.preventDefault()

        const button = event.currentTarget
        const personId = button.dataset.personId

        // For queue mode, we need instance_id; for slot mode, we need slot_id
        if (this.isQueueMode) {
            const instanceId = this.hasInstanceIdTarget ? this.instanceIdTarget.value : ''
            if (!personId || !instanceId) return
            await this.submitQueueRegistration(button, personId, instanceId)
        } else {
            const slotId = this.slotIdTarget.value
            if (!personId || !slotId) return
            await this.submitSlotRegistration(button, personId, slotId)
        }
    }

    async submitSlotRegistration(button, personId, slotId) {
        button.disabled = true
        button.classList.add('opacity-50')

        const formData = new FormData()
        formData.append('slot_id', slotId)
        formData.append('person_id', personId)

        try {
            const response = await fetch(this.registerUrlValue, {
                method: 'POST',
                headers: {
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
                    'Accept': 'text/vnd.turbo-stream.html, text/html, application/xhtml+xml'
                },
                body: formData
            })

            if (response.ok) {
                this.close()
                window.location.reload()
            } else {
                throw new Error('Registration failed')
            }
        } catch (error) {
            console.error('Registration error:', error)
            alert('Failed to add person. Please try again.')
            button.disabled = false
            button.classList.remove('opacity-50')
        }
    }

    async submitQueueRegistration(button, personId, instanceId) {
        button.disabled = true
        button.classList.add('opacity-50')

        const formData = new FormData()
        formData.append('instance_id', instanceId)
        formData.append('person_id', personId)

        try {
            const response = await fetch(this.registerQueueUrlValue, {
                method: 'POST',
                headers: {
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
                    'Accept': 'text/vnd.turbo-stream.html, text/html, application/xhtml+xml'
                },
                body: formData
            })

            if (response.ok) {
                this.close()
                window.location.reload()
            } else {
                throw new Error('Registration failed')
            }
        } catch (error) {
            console.error('Registration error:', error)
            alert('Failed to add person to queue. Please try again.')
            button.disabled = false
            button.classList.remove('opacity-50')
        }
    }

    escapeHtml(text) {
        const div = document.createElement('div')
        div.textContent = text
        return div.innerHTML
    }
}
