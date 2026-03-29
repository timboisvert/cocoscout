import { Controller } from "@hotwired/stimulus"

/**
 * Unified Compose Message Controller
 *
 * Handles opening/closing a message compose modal and submitting messages
 * to various recipient types (person, group, production_team).
 *
 * Usage:
 * - Include the modal partial once per page: render "shared/compose_message_modal"
 * - Add trigger buttons with data attributes:
 *
 *   <button data-controller="compose-message"
 *           data-action="click->compose-message#open"
 *           data-compose-message-recipient-type-value="person"
 *           data-compose-message-recipient-id-value="123"
 *           data-compose-message-recipient-name-value="John Smith">
 *     Contact
 *   </button>
 */
export default class extends Controller {
    static targets = [
        "modal", "modalPanel", "form", "subject", "body", "submitButton",
        "recipientName", "recipientType", "recipientId", "title",
        "recipientSection", "singleRecipient", "recipientHeadshot",
        "batchRecipients", "sendSeparatelySection", "sendSeparately",
        "senderIdentitySection", "senderIdentity", "senderIdentityButton",
        "senderIdentityLabel", "senderIdentityHint",
        // Step 1 targets
        "step1Panel", "step2Panel", "continueButton", "backToStep1", "cancelButton",
        "recipientCards",
        "individualsPanel", "personSearchInput", "selectedPeopleChips",
        "personSearchResults",
        "showCastPanel", "showCastProductionPicker", "showCastProductionSelect",
        "showSelectWrapper", "showSelect",
        "showCastPreview", "showCastCount", "showCastHeadshots",
        "talentPoolPanel", "talentPoolProductionPicker", "talentPoolProductionSelect",
        "talentPoolPreviewBox", "talentPoolCount", "talentPoolHeadshots"
    ]
    static values = {
        recipientType: String,  // "person", "group", "production_team", "show_cast", "batch", "talent_pool"
        recipientId: Number,
        recipientName: String,
        recipientHeadshot: String,  // URL to headshot image
        recipientInitials: String,  // Initials if no headshot
        castMembers: Array,          // Array of {name, headshot} for show_cast type
        batchPersonIds: Array,       // Array of person IDs for batch mode
        scriptId: String,            // ID of script tag containing ALL data as JSON
        productionId: Number,        // Production ID for talent_pool messages
        // Step-select mode data
        shows: Array,                // Array of {id, name, date, cast_count, cast_members}
        talentPoolId: Number,
        talentPoolName: String,
        talentPoolMembers: Array,    // Array of {id, name, headshot, initials}
        talentPoolCount: Number,     // Total count of talent pool members
        searchUrl: String,           // URL for org-level person search endpoint
        // Index page: multiple productions
        productions: Array,          // Array of {id, name} for production picker
        productionDataUrl: String,   // URL pattern for fetching production data JSON
        // Talent pool mode
        singleTalentPool: Boolean,   // Whether org uses a single talent pool
        orgTalentPool: Object        // Pre-loaded org talent pool data {id, name, count, members}
    }

    connect() {
        this.keyHandler = this.handleKeydown.bind(this)
        this.templateSubjectValue = ''
        this.templateBodyValue = ''
        this.stepSelectMode = false
        this.selectedPeople = [] // {id, name, headshot, initials}
        this.searchTimeout = null
    }

    disconnect() {
        document.removeEventListener('keydown', this.keyHandler)
    }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            this.close()
        }
    }

    // Open modal in step-select mode (from "Send a Message" button)
    openWithSteps(event) {
        event?.preventDefault()

        const modal = document.getElementById('compose-message-modal')
        if (!modal) return

        // Get the modal's controller instance (may differ from `this` if triggered from another element)
        const modalController = this.application.getControllerForElementAndIdentifier(modal, 'compose-message') || this

        modalController.stepSelectMode = true
        modalController.selectedPeople = []
        modalController._showCastProductionLoaded = false
        modalController._talentPoolProductionLoaded = false

        // Read data from the trigger element
        const trigger = event?.currentTarget
        const sources = [trigger, this.element].filter(Boolean)
        for (const source of sources) {
            if (source.dataset.composeMessageProductionIdValue) {
                modalController.productionIdValue = parseInt(source.dataset.composeMessageProductionIdValue)
            }
            if (source.dataset.composeMessageShowsValue) {
                try { modalController.showsValue = JSON.parse(source.dataset.composeMessageShowsValue) } catch (e) { modalController.showsValue = [] }
            }
            if (source.dataset.composeMessageTalentPoolIdValue) {
                modalController.talentPoolIdValue = parseInt(source.dataset.composeMessageTalentPoolIdValue)
            }
            if (source.dataset.composeMessageTalentPoolNameValue) {
                modalController.talentPoolNameValue = source.dataset.composeMessageTalentPoolNameValue
            }
            if (source.dataset.composeMessageTalentPoolMembersValue) {
                try { modalController.talentPoolMembersValue = JSON.parse(source.dataset.composeMessageTalentPoolMembersValue) } catch (e) { modalController.talentPoolMembersValue = [] }
            }
            if (source.dataset.composeMessageTalentPoolCountValue) {
                modalController.talentPoolCountValue = parseInt(source.dataset.composeMessageTalentPoolCountValue)
            }
            if (source.dataset.composeMessageSearchUrlValue) {
                modalController.searchUrlValue = source.dataset.composeMessageSearchUrlValue
            }
            if (source.dataset.composeMessageProductionsValue) {
                try { modalController.productionsValue = JSON.parse(source.dataset.composeMessageProductionsValue) } catch (e) { modalController.productionsValue = [] }
            }
            if (source.dataset.composeMessageProductionDataUrlValue) {
                modalController.productionDataUrlValue = source.dataset.composeMessageProductionDataUrlValue
            }
            if (source.dataset.composeMessageSingleTalentPoolValue) {
                modalController.singleTalentPoolValue = source.dataset.composeMessageSingleTalentPoolValue === 'true'
            }
            if (source.dataset.composeMessageOrgTalentPoolValue) {
                try { modalController.orgTalentPoolValue = JSON.parse(source.dataset.composeMessageOrgTalentPoolValue) } catch (e) { modalController.orgTalentPoolValue = {} }
            }
        }

        // If production is already known, mark data as loaded
        if (modalController.productionIdValue) {
            modalController._showCastProductionLoaded = true
            modalController._talentPoolProductionLoaded = true
        }

        // Widen modal for step 1
        const panel = modal.querySelector('[data-compose-message-target="modalPanel"]')
        if (panel) {
            panel.classList.remove('max-w-lg')
            panel.classList.add('max-w-2xl')
        }

        // Show step 1, hide step 2
        const step1 = modal.querySelector('[data-compose-message-target="step1Panel"]')
        const step2 = modal.querySelector('[data-compose-message-target="step2Panel"]')
        if (step1) step1.classList.remove('hidden')
        if (step2) step2.classList.add('hidden')

        // Hide sub-panels
        modalController._hideAllSubPanels(modal)

        // Reset option-select
        const optionSelect = step1?.querySelector('[data-controller="option-select"]')
        if (optionSelect) {
            const controller = this.application.getControllerForElementAndIdentifier(optionSelect, 'option-select')
            if (controller) {
                controller.selectedValue = ''
            }
        }

        // Disable continue button
        const continueBtn = modal.querySelector('[data-compose-message-target="continueButton"]')
        if (continueBtn) continueBtn.disabled = true

        // Cards are always enabled — production selection is deferred to sub-panels
        const recipientCards = modal.querySelector('[data-compose-message-target="recipientCards"]')
        if (recipientCards) recipientCards.classList.remove('opacity-50', 'pointer-events-none')

        // Set title
        const titleEl = modal.querySelector('[data-compose-message-target="title"]')
        if (titleEl) titleEl.textContent = 'Send Message'

        // Show modal
        modal.classList.remove('hidden')
        document.addEventListener('keydown', modalController.keyHandler)
        document.body.classList.add('overflow-hidden')

        // Listen for option-select changes
        modalController._observeStep1Selection(modal)
    }

    // Handle production selection for Show Cast sub-panel
    async selectProductionForShowCast(event) {
        const productionId = event.currentTarget.value
        const modal = document.getElementById('compose-message-modal')
        if (!modal) return

        const showSelectWrapper = modal.querySelector('[data-compose-message-target="showSelectWrapper"]')
        const showPreview = modal.querySelector('[data-compose-message-target="showCastPreview"]')
        const continueBtn = modal.querySelector('[data-compose-message-target="continueButton"]')

        if (!productionId) {
            if (showSelectWrapper) showSelectWrapper.classList.add('hidden')
            if (showPreview) showPreview.classList.add('hidden')
            if (continueBtn) continueBtn.disabled = true
            return
        }

        this.productionIdValue = parseInt(productionId)
        await this._fetchProductionData(productionId)
        this._populateShowDropdown(modal)
        if (showSelectWrapper) showSelectWrapper.classList.remove('hidden')
        this._showCastProductionLoaded = true
        this._talentPoolProductionLoaded = true

        // Reset show selection
        const showSelect = modal.querySelector('[data-compose-message-target="showSelect"]')
        if (showSelect) showSelect.value = ''
        if (showPreview) showPreview.classList.add('hidden')
        if (continueBtn) continueBtn.disabled = true
    }

    // Handle production selection for Talent Pool sub-panel
    async selectProductionForTalentPool(event) {
        const productionId = event.currentTarget.value
        const modal = document.getElementById('compose-message-modal')
        if (!modal) return

        const previewBox = modal.querySelector('[data-compose-message-target="talentPoolPreviewBox"]')
        const continueBtn = modal.querySelector('[data-compose-message-target="continueButton"]')

        if (!productionId) {
            if (previewBox) previewBox.classList.add('hidden')
            if (continueBtn) continueBtn.disabled = true
            return
        }

        this.productionIdValue = parseInt(productionId)
        await this._fetchProductionData(productionId)
        this._populateTalentPoolPreview(modal)
        this._talentPoolProductionLoaded = true
        this._showCastProductionLoaded = true

        if (previewBox) previewBox.classList.remove('hidden')
        if (continueBtn) continueBtn.disabled = !!(!this.talentPoolIdValue)
    }

    // Shared method to fetch production data from server
    async _fetchProductionData(productionId) {
        const url = this.productionDataUrlValue.replace(':production_id', productionId)
        try {
            const response = await fetch(url, { headers: { 'Accept': 'application/json' } })
            if (!response.ok) throw new Error('Failed to fetch production data')

            const data = await response.json()

            this.showsValue = data.shows || []

            if (data.talent_pool) {
                this.talentPoolIdValue = data.talent_pool.id
                this.talentPoolNameValue = data.talent_pool.name
                this.talentPoolMembersValue = data.talent_pool.members || []
                this.talentPoolCountValue = data.talent_pool.count || 0
            } else {
                this.talentPoolIdValue = 0
                this.talentPoolNameValue = ''
                this.talentPoolMembersValue = []
                this.talentPoolCountValue = 0
            }
        } catch (error) {
            console.error('Failed to load production data:', error)
        }
    }

    _populateProductionSelect(selectEl) {
        if (!selectEl) return

        // Clear options except placeholder
        while (selectEl.options.length > 1) selectEl.remove(1)

        const productions = this.productionsValue || []
        productions.forEach(prod => {
            const opt = document.createElement('option')
            opt.value = prod.id
            opt.textContent = prod.name
            selectEl.appendChild(opt)
        })

        // Preserve the currently selected production if one is set
        if (this.productionIdValue) {
            selectEl.value = this.productionIdValue
        } else {
            selectEl.value = ''
        }
    }

    _hideAllSubPanels(modal) {
        const panels = ['individualsPanel', 'showCastPanel', 'talentPoolPanel']
        panels.forEach(name => {
            const el = modal.querySelector(`[data-compose-message-target="${name}"]`)
            if (el) el.classList.add('hidden')
        })
    }

    _observeStep1Selection(modal) {
        const step1 = modal.querySelector('[data-compose-message-target="step1Panel"]')
        if (!step1) return

        const optionContainer = step1.querySelector('[data-controller="option-select"]')
        if (!optionContainer) return

        optionContainer.addEventListener('click', () => {
            setTimeout(() => this._onStep1TypeSelected(modal), 50)
        })
    }

    _onStep1TypeSelected(modal) {
        const selected = modal.querySelector('input[name="step1_recipient_type"]:checked')?.value
        if (!selected) return

        this._hideAllSubPanels(modal)

        const continueBtn = modal.querySelector('[data-compose-message-target="continueButton"]')
        const hasMultipleProductions = this.productionsValue?.length > 0

        if (selected === 'individuals') {
            // Individuals never needs a production — show search immediately
            const panel = modal.querySelector('[data-compose-message-target="individualsPanel"]')
            if (panel) panel.classList.remove('hidden')
            const searchInput = modal.querySelector('[data-compose-message-target="personSearchInput"]')
            if (searchInput) setTimeout(() => searchInput.focus(), 100)
            if (continueBtn) continueBtn.disabled = this.selectedPeople.length === 0

        } else if (selected === 'show_cast') {
            const panel = modal.querySelector('[data-compose-message-target="showCastPanel"]')
            if (panel) panel.classList.remove('hidden')

            if (hasMultipleProductions) {
                // Always show production picker when there are multiple productions
                const picker = modal.querySelector('[data-compose-message-target="showCastProductionPicker"]')
                if (picker) picker.classList.remove('hidden')
                const select = modal.querySelector('[data-compose-message-target="showCastProductionSelect"]')
                this._populateProductionSelect(select)

                if (this._showCastProductionLoaded || this._talentPoolProductionLoaded) {
                    // Production already selected (possibly from the other tab) — show sub-content
                    this._showCastProductionLoaded = true
                    const showSelectWrapper = modal.querySelector('[data-compose-message-target="showSelectWrapper"]')
                    if (showSelectWrapper) showSelectWrapper.classList.remove('hidden')
                    this._populateShowDropdown(modal)
                    const showSelect = modal.querySelector('[data-compose-message-target="showSelect"]')
                    if (continueBtn) continueBtn.disabled = !showSelect?.value
                } else {
                    // No production yet — hide show dropdown
                    const showSelectWrapper = modal.querySelector('[data-compose-message-target="showSelectWrapper"]')
                    if (showSelectWrapper) showSelectWrapper.classList.add('hidden')
                    if (continueBtn) continueBtn.disabled = true
                }
            } else {
                // Single production already known — hide picker, show the show dropdown directly
                const picker = modal.querySelector('[data-compose-message-target="showCastProductionPicker"]')
                if (picker) picker.classList.add('hidden')
                const showSelectWrapper = modal.querySelector('[data-compose-message-target="showSelectWrapper"]')
                if (showSelectWrapper) showSelectWrapper.classList.remove('hidden')
                this._populateShowDropdown(modal)
                const showSelect = modal.querySelector('[data-compose-message-target="showSelect"]')
                if (continueBtn) continueBtn.disabled = !showSelect?.value
            }

        } else if (selected === 'talent_pool') {
            const panel = modal.querySelector('[data-compose-message-target="talentPoolPanel"]')
            if (panel) panel.classList.remove('hidden')

            if (this.singleTalentPoolValue && this.orgTalentPoolValue?.id) {
                // Single org talent pool — auto-load, no production picker needed
                this.talentPoolIdValue = this.orgTalentPoolValue.id
                this.talentPoolNameValue = this.orgTalentPoolValue.name
                this.talentPoolMembersValue = this.orgTalentPoolValue.members || []
                this.talentPoolCountValue = this.orgTalentPoolValue.count || 0
                const picker = modal.querySelector('[data-compose-message-target="talentPoolProductionPicker"]')
                if (picker) picker.classList.add('hidden')
                this._populateTalentPoolPreview(modal)
                const previewBox = modal.querySelector('[data-compose-message-target="talentPoolPreviewBox"]')
                if (previewBox) previewBox.classList.remove('hidden')
                if (continueBtn) continueBtn.disabled = false
            } else if (hasMultipleProductions) {
                // Always show production picker when there are multiple productions
                const picker = modal.querySelector('[data-compose-message-target="talentPoolProductionPicker"]')
                if (picker) picker.classList.remove('hidden')
                const select = modal.querySelector('[data-compose-message-target="talentPoolProductionSelect"]')
                this._populateProductionSelect(select)

                if (this._talentPoolProductionLoaded || this._showCastProductionLoaded) {
                    // Production already selected (possibly from the other tab) — show preview
                    this._talentPoolProductionLoaded = true
                    this._populateTalentPoolPreview(modal)
                    const previewBox = modal.querySelector('[data-compose-message-target="talentPoolPreviewBox"]')
                    if (previewBox) previewBox.classList.remove('hidden')
                    if (continueBtn) continueBtn.disabled = !this.talentPoolIdValue
                } else {
                    // No production yet — hide preview
                    const previewBox = modal.querySelector('[data-compose-message-target="talentPoolPreviewBox"]')
                    if (previewBox) previewBox.classList.add('hidden')
                    if (continueBtn) continueBtn.disabled = true
                }
            } else {
                // Single production already known — hide picker, show preview directly
                const picker = modal.querySelector('[data-compose-message-target="talentPoolProductionPicker"]')
                if (picker) picker.classList.add('hidden')
                this._populateTalentPoolPreview(modal)
                const previewBox = modal.querySelector('[data-compose-message-target="talentPoolPreviewBox"]')
                if (previewBox) previewBox.classList.remove('hidden')
                if (continueBtn) continueBtn.disabled = !this.talentPoolIdValue
            }
        }
    }

    _populateShowDropdown(modal) {
        const select = modal.querySelector('[data-compose-message-target="showSelect"]')
        if (!select) return

        while (select.options.length > 1) select.remove(1)

        const shows = this.showsValue || []
        shows.forEach(show => {
            const opt = document.createElement('option')
            opt.value = show.id
            opt.textContent = `${show.name} — ${show.date}`
            opt.dataset.castCount = show.cast_count
            opt.dataset.castMembers = JSON.stringify(show.cast_members || [])
            select.appendChild(opt)
        })
    }

    _populateTalentPoolPreview(modal) {
        const countEl = modal.querySelector('[data-compose-message-target="talentPoolCount"]')
        const headshotsEl = modal.querySelector('[data-compose-message-target="talentPoolHeadshots"]')
        const members = this.talentPoolMembersValue || []
        const totalCount = this.talentPoolCountValue || members.length

        if (countEl) countEl.textContent = totalCount
        if (headshotsEl) {
            headshotsEl.innerHTML = this.renderStackedHeadshots(
                members.map(m => ({ name: m.name, headshot: m.headshot }))
            )
        }
    }

    selectShow(event) {
        const modal = document.getElementById('compose-message-modal')
        if (!modal) return

        const select = event.currentTarget
        const selectedOption = select.options[select.selectedIndex]
        const castCount = parseInt(selectedOption?.dataset?.castCount || '0')
        const castMembers = selectedOption?.dataset?.castMembers ? JSON.parse(selectedOption.dataset.castMembers) : []

        const preview = modal.querySelector('[data-compose-message-target="showCastPreview"]')
        const countEl = modal.querySelector('[data-compose-message-target="showCastCount"]')
        const headshotsEl = modal.querySelector('[data-compose-message-target="showCastHeadshots"]')
        const continueBtn = modal.querySelector('[data-compose-message-target="continueButton"]')

        if (select.value) {
            if (preview) preview.classList.remove('hidden')
            if (countEl) countEl.textContent = castCount
            if (headshotsEl) headshotsEl.innerHTML = this.renderStackedHeadshots(castMembers)
            if (continueBtn) continueBtn.disabled = false
        } else {
            if (preview) preview.classList.add('hidden')
            if (continueBtn) continueBtn.disabled = true
        }
    }

    // Person search for individuals panel
    searchPeople(event) {
        const query = event.currentTarget.value.trim()
        const modal = document.getElementById('compose-message-modal')
        const resultsEl = modal?.querySelector('[data-compose-message-target="personSearchResults"]')

        if (!resultsEl) return

        if (query.length < 2) {
            resultsEl.classList.add('hidden')
            resultsEl.innerHTML = ''
            return
        }

        // Debounce
        clearTimeout(this.searchTimeout)
        this.searchTimeout = setTimeout(async () => {
            const url = this.searchUrlValue
            if (!url) return

            try {
                const response = await fetch(`${url}?q=${encodeURIComponent(query)}`, {
                    headers: { 'Accept': 'application/json' }
                })
                if (!response.ok) return

                const data = await response.json()
                const people = data.people || []

                // Filter out already selected
                const selectedIds = new Set(this.selectedPeople.map(p => p.id))
                const filtered = people.filter(p => !selectedIds.has(p.id))

                if (filtered.length === 0) {
                    resultsEl.innerHTML = '<div class="px-4 py-3 text-sm text-gray-500">No results found</div>'
                    resultsEl.classList.remove('hidden')
                    return
                }

                resultsEl.innerHTML = filtered.map(person => `
                    <button type="button"
                            class="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-pink-50 transition-colors cursor-pointer text-left"
                            data-action="click->compose-message#addPerson"
                            data-person-id="${person.id}"
                            data-person-name="${this._escapeHtml(person.name)}"
                            data-person-headshot="${person.headshot_url || ''}"
                            data-person-initials="${this._escapeHtml(person.initials || this.getInitials(person.name))}">
                        ${person.headshot_url
                        ? `<img src="${person.headshot_url}" alt="${this._escapeHtml(person.name)}" class="w-8 h-8 rounded-lg object-cover">`
                        : `<div class="w-8 h-8 rounded-lg bg-pink-100 flex items-center justify-center text-pink-600 font-bold text-xs">${this._escapeHtml(person.initials || this.getInitials(person.name))}</div>`
                    }
                        <div>
                            <div class="text-sm font-medium text-gray-900">${this._escapeHtml(person.name)}</div>
                            ${person.email ? `<div class="text-xs text-gray-500">${this._escapeHtml(person.email)}</div>` : ''}
                        </div>
                    </button>
                `).join('')
                resultsEl.classList.remove('hidden')
            } catch (error) {
                console.error('Person search failed:', error)
            }
        }, 300)
    }

    addPerson(event) {
        event.preventDefault()
        const btn = event.currentTarget
        const person = {
            id: parseInt(btn.dataset.personId),
            name: btn.dataset.personName,
            headshot: btn.dataset.personHeadshot,
            initials: btn.dataset.personInitials
        }

        // Avoid duplicates
        if (this.selectedPeople.find(p => p.id === person.id)) return

        this.selectedPeople.push(person)
        this._renderSelectedChips()

        // Clear search
        const modal = document.getElementById('compose-message-modal')
        const searchInput = modal?.querySelector('[data-compose-message-target="personSearchInput"]')
        const resultsEl = modal?.querySelector('[data-compose-message-target="personSearchResults"]')
        if (searchInput) searchInput.value = ''
        if (resultsEl) { resultsEl.classList.add('hidden'); resultsEl.innerHTML = '' }

        // Enable continue button
        const continueBtn = modal?.querySelector('[data-compose-message-target="continueButton"]')
        if (continueBtn) continueBtn.disabled = false

        // Re-focus search input
        if (searchInput) searchInput.focus()
    }

    removePerson(event) {
        event.preventDefault()
        const personId = parseInt(event.currentTarget.dataset.personId)
        this.selectedPeople = this.selectedPeople.filter(p => p.id !== personId)
        this._renderSelectedChips()

        // Disable continue if no people selected
        const modal = document.getElementById('compose-message-modal')
        const continueBtn = modal?.querySelector('[data-compose-message-target="continueButton"]')
        if (continueBtn) continueBtn.disabled = this.selectedPeople.length === 0
    }

    _renderSelectedChips() {
        const modal = document.getElementById('compose-message-modal')
        const chipsEl = modal?.querySelector('[data-compose-message-target="selectedPeopleChips"]')
        if (!chipsEl) return

        chipsEl.innerHTML = this.selectedPeople.map(person => `
            <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-pink-100 text-pink-700 text-sm">
                ${person.headshot
                ? `<img src="${person.headshot}" class="w-5 h-5 rounded-lg object-cover">`
                : `<span class="w-5 h-5 rounded-lg bg-pink-200 flex items-center justify-center text-pink-700 text-[10px] font-bold">${this._escapeHtml(person.initials)}</span>`
            }
                ${this._escapeHtml(person.name)}
                <button type="button"
                        class="ml-0.5 text-pink-400 hover:text-pink-600 cursor-pointer"
                        data-action="click->compose-message#removePerson"
                        data-person-id="${person.id}">
                    <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                    </svg>
                </button>
            </span>
        `).join('')
    }

    _escapeHtml(text) {
        const div = document.createElement('div')
        div.textContent = text || ''
        return div.innerHTML
    }

    // Transition from step 1 to step 2 (compose form)
    continueToCompose(event) {
        event?.preventDefault()
        const modal = document.getElementById('compose-message-modal')
        if (!modal) return

        const selected = modal.querySelector('input[name="step1_recipient_type"]:checked')?.value
        if (!selected) return

        if (selected === 'individuals') {
            if (this.selectedPeople.length === 1) {
                // Single person - set as person recipient
                const person = this.selectedPeople[0]
                this.recipientTypeValue = 'person'
                this.recipientIdValue = person.id
                this.recipientNameValue = person.name
                this.recipientHeadshotValue = person.headshot || ''
                this.recipientInitialsValue = person.initials || this.getInitials(person.name)
                this.castMembersValue = []
                this.batchPersonIdsValue = []
            } else {
                // Multiple people - batch mode
                this.recipientTypeValue = 'batch'
                this.recipientIdValue = null
                this.recipientNameValue = ''
                this.batchPersonIdsValue = this.selectedPeople.map(p => p.id)
                this.castMembersValue = this.selectedPeople.map(p => ({ name: p.name, headshot: p.headshot || '' }))
            }
        } else if (selected === 'show_cast') {
            const showSelect = modal.querySelector('[data-compose-message-target="showSelect"]')
            const selectedOption = showSelect?.options[showSelect.selectedIndex]
            const showId = showSelect?.value
            const showName = selectedOption?.textContent || ''
            const castMembers = selectedOption?.dataset?.castMembers ? JSON.parse(selectedOption.dataset.castMembers) : []

            this.recipientTypeValue = 'show_cast'
            this.recipientIdValue = parseInt(showId)
            this.recipientNameValue = showName.split(' — ')[0]?.trim() || showName
            this.castMembersValue = castMembers
            this.batchPersonIdsValue = []
        } else if (selected === 'talent_pool') {
            this.recipientTypeValue = 'talent_pool'
            this.recipientIdValue = this.talentPoolIdValue
            this.recipientNameValue = this.talentPoolNameValue || 'Talent Pool'
            this.castMembersValue = (this.talentPoolMembersValue || []).map(m => ({ name: m.name, headshot: m.headshot || '' }))
            this.batchPersonIdsValue = []
        }

        // Narrow modal back to original width
        const panel = modal.querySelector('[data-compose-message-target="modalPanel"]')
        if (panel) {
            panel.classList.remove('max-w-2xl')
            panel.classList.add('max-w-lg')
        }

        // Switch panels
        const step1 = modal.querySelector('[data-compose-message-target="step1Panel"]')
        const step2 = modal.querySelector('[data-compose-message-target="step2Panel"]')
        if (step1) step1.classList.add('hidden')
        if (step2) step2.classList.remove('hidden')

        // Show back button, hide cancel
        const backBtn = modal.querySelector('[data-compose-message-target="backToStep1"]')
        if (backBtn) backBtn.classList.remove('hidden')
        const cancelBtn = modal.querySelector('[data-compose-message-target="cancelButton"]')
        if (cancelBtn) cancelBtn.classList.add('hidden')

        // Now use the existing _openModal flow to populate step 2
        this._openModal()
    }

    backToStep1(event) {
        event?.preventDefault()
        const modal = document.getElementById('compose-message-modal')
        if (!modal) return

        // Save current show selection before re-triggering sub-panels
        const showSelect = modal.querySelector('[data-compose-message-target="showSelect"]')
        const savedShowValue = showSelect?.value

        // Widen modal for step 1
        const panel = modal.querySelector('[data-compose-message-target="modalPanel"]')
        if (panel) {
            panel.classList.remove('max-w-lg')
            panel.classList.add('max-w-2xl')
        }

        // Switch panels
        const step1 = modal.querySelector('[data-compose-message-target="step1Panel"]')
        const step2 = modal.querySelector('[data-compose-message-target="step2Panel"]')
        if (step1) step1.classList.remove('hidden')
        if (step2) step2.classList.add('hidden')

        // Show cancel, hide back
        const cancelBtn = modal.querySelector('[data-compose-message-target="cancelButton"]')
        if (cancelBtn) cancelBtn.classList.remove('hidden')

        // Re-trigger sub-panel display
        this._onStep1TypeSelected(modal)

        // Restore show selection and preview if it was set
        if (savedShowValue && showSelect) {
            showSelect.value = savedShowValue
            // Re-trigger the preview for the restored selection
            showSelect.dispatchEvent(new Event('change', { bubbles: true }))
        }
    }

    // New method that loads ALL data from a script tag - no data attributes needed
    openFromScript(event) {
        event?.preventDefault()

        const scriptId = this.scriptIdValue
        if (!scriptId) {
            console.error('No script ID provided')
            return
        }

        const scriptTag = document.getElementById(scriptId)
        if (!scriptTag) {
            console.error('Script tag not found:', scriptId)
            return
        }

        let data
        try {
            data = JSON.parse(scriptTag.textContent)
        } catch (e) {
            console.error('Failed to parse script data:', e)
            return
        }

        // Set all values from the script data
        this.recipientTypeValue = data.recipientType || ''
        this.recipientNameValue = data.recipientName || ''
        this.castMembersValue = data.castMembers || []
        this.batchPersonIdsValue = data.batchPersonIds || []
        this.templateSubjectValue = data.templateSubject || ''
        this.templateBodyValue = data.templateBody || ''

        // Now open the modal with all the data loaded
        this._openModal()
    }

    open(event) {
        event?.preventDefault()

        // Get recipient info from the trigger button's data attributes if provided
        // Check both the trigger element AND this.element (controller element) since
        // the data may be on either one depending on how the button is structured
        const trigger = event?.currentTarget
        const sources = [trigger, this.element].filter(Boolean)

        // Reset template values before reading new ones
        this.templateSubjectValue = ''
        this.templateBodyValue = ''
        this.templateDataIdValue = ''

        for (const source of sources) {
            if (source.dataset.composeMessageRecipientTypeValue) {
                this.recipientTypeValue = source.dataset.composeMessageRecipientTypeValue
            }
            if (source.dataset.composeMessageRecipientIdValue) {
                this.recipientIdValue = parseInt(source.dataset.composeMessageRecipientIdValue)
            }
            if (source.dataset.composeMessageRecipientNameValue) {
                this.recipientNameValue = source.dataset.composeMessageRecipientNameValue
            }
            if (source.dataset.composeMessageRecipientHeadshotValue) {
                this.recipientHeadshotValue = source.dataset.composeMessageRecipientHeadshotValue
            }
            if (source.dataset.composeMessageRecipientInitialsValue) {
                this.recipientInitialsValue = source.dataset.composeMessageRecipientInitialsValue
            }
            if (source.dataset.composeMessageCastMembersValue) {
                try {
                    this.castMembersValue = JSON.parse(source.dataset.composeMessageCastMembersValue)
                } catch (e) {
                    this.castMembersValue = []
                }
            }
            if (source.dataset.composeMessageBatchPersonIdsValue) {
                try {
                    this.batchPersonIdsValue = JSON.parse(source.dataset.composeMessageBatchPersonIdsValue)
                } catch (e) {
                    this.batchPersonIdsValue = []
                }
            }
            if (source.dataset.composeMessageTemplateDataIdValue && !this.templateDataIdValue) {
                this.templateDataIdValue = source.dataset.composeMessageTemplateDataIdValue
            }
            if (source.dataset.composeMessageProductionIdValue && !this.productionIdValue) {
                this.productionIdValue = parseInt(source.dataset.composeMessageProductionIdValue)
            }
        }

        // Load template data from script tag if specified
        if (this.templateDataIdValue) {
            const scriptTag = document.getElementById(this.templateDataIdValue)
            if (scriptTag) {
                try {
                    const templateData = JSON.parse(scriptTag.textContent)
                    this.templateSubjectValue = templateData.subject || ''
                    this.templateBodyValue = templateData.body || ''
                } catch (e) {
                    console.error('Failed to parse template data:', e)
                }
            }
        }

        this._openModal()
    }

    _openModal() {
        // Find the modal (it may be outside this controller's element)
        const modal = this.hasModalTarget ? this.modalTarget : document.getElementById('compose-message-modal')
        if (!modal) {
            console.error('Compose message modal not found')
            return
        }

        // Update recipient display
        this.updateRecipientDisplay(modal)

        // Set hidden form fields
        const typeInput = modal.querySelector('[data-compose-message-target="recipientType"]')
        const idInput = modal.querySelector('[data-compose-message-target="recipientId"]')
        if (typeInput) typeInput.value = this.recipientTypeValue
        if (idInput) idInput.value = this.recipientIdValue

        // Handle batch person IDs and production_id field
        const form = modal.querySelector('[data-compose-message-target="form"]')
        if (form) {
            form.querySelectorAll('input[name="person_ids[]"]').forEach(el => el.remove())
            form.querySelectorAll('input[name="production_id"]').forEach(el => el.remove())

            // Add new person_ids for batch mode
            if (this.recipientTypeValue === 'batch' && this.batchPersonIdsValue?.length > 0) {
                this.batchPersonIdsValue.forEach(id => {
                    const input = document.createElement('input')
                    input.type = 'hidden'
                    input.name = 'person_ids[]'
                    input.value = id
                    form.appendChild(input)
                })
            }

            // Add production_id for talent_pool messages
            if (this.recipientTypeValue === 'talent_pool' && this.productionIdValue) {
                const input = document.createElement('input')
                input.type = 'hidden'
                input.name = 'production_id'
                input.value = this.productionIdValue
                form.appendChild(input)
            }

            form.action = this.getFormAction()
        }

        // Show/hide send separately section based on recipient type
        const sendSeparatelySection = modal.querySelector('[data-compose-message-target="sendSeparatelySection"]')
        const sendSeparatelyCheckbox = modal.querySelector('[data-compose-message-target="sendSeparately"]')
        if (sendSeparatelySection) {
            const isBatchOrMultiple = this.recipientTypeValue === 'batch' ||
                (this.recipientTypeValue === 'show_cast' && this.castMembersValue?.length > 1) ||
                (this.recipientTypeValue === 'auditionees' && this.castMembersValue?.length > 1) ||
                (this.recipientTypeValue === 'talent_pool' && this.talentPoolCountValue > 1)
            if (isBatchOrMultiple) {
                sendSeparatelySection.classList.remove('hidden')
            } else {
                sendSeparatelySection.classList.add('hidden')
            }
            // Reset the checkbox
            if (sendSeparatelyCheckbox) {
                sendSeparatelyCheckbox.checked = false
            }
        }

        // Show sender identity section for all message types (person, group, show_cast, talent_pool, batch)
        // This allows users to choose whether to send as "Production Team" or "Just Me"
        const senderIdentitySection = modal.querySelector('[data-compose-message-target="senderIdentitySection"]')
        if (senderIdentitySection) {
            // Always show the sender identity section
            senderIdentitySection.classList.remove('hidden')
            // Reset to production_team by default
            const hiddenInput = senderIdentitySection.querySelector('input[name="sender_identity"]')
            if (hiddenInput) hiddenInput.value = 'production_team'
            const label = senderIdentitySection.querySelector('[data-compose-message-target="senderIdentityLabel"]')
            const hint = senderIdentitySection.querySelector('[data-compose-message-target="senderIdentityHint"]')
            const button = senderIdentitySection.querySelector('[data-compose-message-target="senderIdentityButton"]')
            const iconContainer = button?.querySelector('div:first-child > div:first-child')
            if (label) label.textContent = 'Production Team'
            if (hint) hint.textContent = '(visible to all team members)'
            if (iconContainer) {
                iconContainer.classList.remove('bg-gray-400')
                iconContainer.classList.add('bg-pink-500')
                iconContainer.innerHTML = `<svg class="w-3.5 h-3.5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z" />
                </svg>`
            }
        }

        // Calculate and store recipient count for use in toggleSendSeparately
        const recipientCount = this.batchPersonIdsValue?.length || this.castMembersValue?.length || 1
        modal.dataset.recipientCount = recipientCount

        // Reset submit button text
        const submitButton = modal.querySelector('[data-compose-message-target="submitButton"]')
        if (submitButton) {
            const textTarget = submitButton.querySelector('span') || submitButton
            if (recipientCount > 1) {
                textTarget.textContent = `Send to ${recipientCount} People`
            } else {
                textTarget.textContent = 'Send Message'
            }
        }

        // Pre-fill subject and body from template if provided
        const subjectInput = modal.querySelector('[data-compose-message-target="subject"]')
        const bodyInput = modal.querySelector('trix-editor')

        if (subjectInput && this.templateSubjectValue) {
            subjectInput.value = this.templateSubjectValue
        }

        if (bodyInput && this.templateBodyValue) {
            // Convert simple markdown to HTML for Trix
            const html = this.markdownToHtml(this.templateBodyValue)
            bodyInput.editor.loadHTML(html)
        }

        // Show modal
        modal.classList.remove('hidden')
        document.addEventListener('keydown', this.keyHandler)
        document.body.classList.add('overflow-hidden')

        // Focus the subject field
        if (subjectInput) {
            setTimeout(() => subjectInput.focus(), 100)
        }
    }

    updateRecipientDisplay(modal) {
        const singleRecipient = modal.querySelector('[data-compose-message-target="singleRecipient"]')
        const batchRecipients = modal.querySelector('[data-compose-message-target="batchRecipients"]')
        const nameTarget = modal.querySelector('[data-compose-message-target="recipientName"]')
        const headshotTarget = modal.querySelector('[data-compose-message-target="recipientHeadshot"]')

        // For show_cast, talent_pool, or auditionees with cast members - always show name label + headshots
        if ((this.recipientTypeValue === 'show_cast' || this.recipientTypeValue === 'talent_pool' || this.recipientTypeValue === 'auditionees') && this.castMembersValue?.length > 0) {
            if (singleRecipient) singleRecipient.classList.add('hidden')
            if (batchRecipients) {
                batchRecipients.classList.remove('hidden')
                // Add the recipient name (e.g., "Comedy Pageant Cast") before headshots
                const nameLabel = this.recipientNameValue ? `<span class="text-sm font-medium text-gray-900 mr-2">${this.recipientNameValue}</span>` : ''
                batchRecipients.innerHTML = nameLabel + this.renderStackedHeadshots(this.castMembersValue)
            }
            return
        }

        // For batch mode with cast members data, show stacked headshots
        if (this.recipientTypeValue === 'batch' && this.castMembersValue?.length > 0) {
            if (singleRecipient) singleRecipient.classList.add('hidden')
            if (batchRecipients) {
                batchRecipients.classList.remove('hidden')
                batchRecipients.innerHTML = this.renderStackedHeadshots(this.castMembersValue)
            }
            return
        }

        // For single recipients (person, group, etc.), show single recipient display
        if (singleRecipient) singleRecipient.classList.remove('hidden')
        if (batchRecipients) batchRecipients.classList.add('hidden')

        // Update name
        if (nameTarget) {
            nameTarget.textContent = this.recipientNameValue || 'Unknown'
        }

        // Update headshot
        if (headshotTarget) {
            if (this.recipientHeadshotValue) {
                headshotTarget.innerHTML = `<img src="${this.recipientHeadshotValue}" alt="${this.recipientNameValue}" class="w-8 h-8 rounded-lg object-cover ring-2 ring-white">`
            } else {
                const initials = this.recipientInitialsValue || this.getInitials(this.recipientNameValue)
                headshotTarget.innerHTML = initials
                headshotTarget.className = 'w-8 h-8 rounded-lg bg-pink-100 flex items-center justify-center text-pink-600 font-bold text-xs ring-2 ring-white'
            }
        }
    }

    renderStackedHeadshots(members) {
        const maxVisible = 8
        const visibleMembers = members.slice(0, maxVisible)
        const overflowCount = members.length - maxVisible

        let html = visibleMembers.map(member => {
            const initials = member.name ? member.name.split(' ').map(n => n[0]).join('').toUpperCase().substring(0, 2) : '?'
            const headshot = member.headshot

            if (headshot) {
                return `
                    <span data-controller="tooltip" data-tooltip-text-value="${member.name}" class="relative">
                        <img src="${headshot}" alt="${member.name}"
                             class="w-8 h-8 rounded-lg object-cover ring-2 ring-white relative z-10 hover:z-20 hover:scale-110 transition-transform cursor-default">
                    </span>`
            } else {
                return `
                    <span data-controller="tooltip" data-tooltip-text-value="${member.name}" class="relative">
                        <div class="w-8 h-8 rounded-lg bg-pink-100 flex items-center justify-center text-pink-600 font-bold text-xs ring-2 ring-white relative z-10 hover:z-20 hover:scale-110 transition-transform cursor-default">
                            ${initials}
                        </div>
                    </span>`
            }
        }).join('')

        if (overflowCount > 0) {
            html += `
                <span data-controller="tooltip" data-tooltip-text-value="${overflowCount} more" class="relative">
                    <div class="w-8 h-8 rounded-lg bg-gray-200 flex items-center justify-center text-gray-600 font-bold text-xs ring-2 ring-white relative z-10">
                        +${overflowCount}
                    </div>
                </span>`
        }

        return html
    }

    getInitials(name) {
        if (!name) return '?'
        return name.split(' ').map(n => n[0]).join('').toUpperCase().substring(0, 2)
    }

    getFormAction() {
        // All message types now go through the unified endpoint
        return '/manage/messages'
    }

    toggleSendSeparately(event) {
        const modal = this.hasModalTarget ? this.modalTarget : document.getElementById('compose-message-modal')
        const submitButton = modal?.querySelector('[data-compose-message-target="submitButton"]')
        const isChecked = event.target.checked

        if (submitButton && modal) {
            // Get recipient count from data attribute stored when modal opened
            const recipientCount = parseInt(modal.dataset.recipientCount) || 1
            const textTarget = submitButton.querySelector('span') || submitButton
            if (isChecked && recipientCount > 1) {
                textTarget.textContent = `Send to ${recipientCount} People Separately`
            } else if (recipientCount > 1) {
                textTarget.textContent = `Send to ${recipientCount} People`
            } else {
                textTarget.textContent = 'Send Message'
            }
        }
    }

    close() {
        const modal = this.hasModalTarget ? this.modalTarget : document.getElementById('compose-message-modal')
        if (modal) {
            modal.classList.add('hidden')
            document.removeEventListener('keydown', this.keyHandler)
            document.body.classList.remove('overflow-hidden')

            // Reset step-select state
            this.stepSelectMode = false
            this.selectedPeople = []
            const step1 = modal.querySelector('[data-compose-message-target="step1Panel"]')
            const step2 = modal.querySelector('[data-compose-message-target="step2Panel"]')
            if (step1) step1.classList.add('hidden')
            if (step2) step2.classList.remove('hidden')
            const backBtn = modal.querySelector('[data-compose-message-target="backToStep1"]')
            if (backBtn) backBtn.classList.add('hidden')
            const cancelBtn = modal.querySelector('[data-compose-message-target="cancelButton"]')
            if (cancelBtn) cancelBtn.classList.remove('hidden')
            // Reset modal width
            const panel = modal.querySelector('[data-compose-message-target="modalPanel"]')
            if (panel) {
                panel.classList.remove('max-w-2xl')
                panel.classList.add('max-w-lg')
            }
            // Reset search and chips
            const searchInput = modal.querySelector('[data-compose-message-target="personSearchInput"]')
            if (searchInput) searchInput.value = ''
            const searchResults = modal.querySelector('[data-compose-message-target="personSearchResults"]')
            if (searchResults) { searchResults.classList.add('hidden'); searchResults.innerHTML = '' }
            const chips = modal.querySelector('[data-compose-message-target="selectedPeopleChips"]')
            if (chips) chips.innerHTML = ''
            // Reset show dropdown
            const showSelect = modal.querySelector('[data-compose-message-target="showSelect"]')
            if (showSelect) showSelect.value = ''
            const showPreview = modal.querySelector('[data-compose-message-target="showCastPreview"]')
            if (showPreview) showPreview.classList.add('hidden')
            // Reset production pickers in sub-panels
            const showCastProdPicker = modal.querySelector('[data-compose-message-target="showCastProductionPicker"]')
            if (showCastProdPicker) showCastProdPicker.classList.add('hidden')
            const showCastProdSelect = modal.querySelector('[data-compose-message-target="showCastProductionSelect"]')
            if (showCastProdSelect) showCastProdSelect.value = ''
            const talentPoolProdPicker = modal.querySelector('[data-compose-message-target="talentPoolProductionPicker"]')
            if (talentPoolProdPicker) talentPoolProdPicker.classList.add('hidden')
            const talentPoolProdSelect = modal.querySelector('[data-compose-message-target="talentPoolProductionSelect"]')
            if (talentPoolProdSelect) talentPoolProdSelect.value = ''
            const showSelectWrapper = modal.querySelector('[data-compose-message-target="showSelectWrapper"]')
            if (showSelectWrapper) showSelectWrapper.classList.add('hidden')
            const talentPoolPreviewBox = modal.querySelector('[data-compose-message-target="talentPoolPreviewBox"]')
            if (talentPoolPreviewBox) talentPoolPreviewBox.classList.add('hidden')
            this._showCastProductionLoaded = false
            this._talentPoolProductionLoaded = false

            // Reset form
            const form = modal.querySelector('[data-compose-message-target="form"]')
            if (form) {
                form.reset()
                // Remove any dynamically added person_ids fields (from batch mode)
                form.querySelectorAll('input[name="person_ids[]"]').forEach(el => el.remove())

                // Reset Trix editor content
                const trixEditor = form.querySelector('trix-editor')
                if (trixEditor && trixEditor.editor) {
                    trixEditor.editor.loadHTML('')
                }
            }

            // Reset title
            const titleTarget = modal.querySelector('[data-compose-message-target="title"]')
            if (titleTarget) {
                titleTarget.textContent = 'Send Message'
            }

            // Reset recipient display
            const singleRecipient = modal.querySelector('[data-compose-message-target="singleRecipient"]')
            const batchRecipients = modal.querySelector('[data-compose-message-target="batchRecipients"]')
            if (singleRecipient) singleRecipient.classList.remove('hidden')
            if (batchRecipients) {
                batchRecipients.classList.add('hidden')
                batchRecipients.innerHTML = ''
            }

            // Reset send separately section
            const sendSeparatelySection = modal.querySelector('[data-compose-message-target="sendSeparatelySection"]')
            const sendSeparatelyCheckbox = modal.querySelector('[data-compose-message-target="sendSeparately"]')
            if (sendSeparatelySection) {
                sendSeparatelySection.classList.add('hidden')
            }
            if (sendSeparatelyCheckbox) {
                sendSeparatelyCheckbox.checked = false
            }

            // Reset poll section via its Stimulus controller
            const pollComposerEl = modal.querySelector('[data-controller="poll-composer"]')
            if (pollComposerEl) {
                const pollController = this.application.getControllerForElementAndIdentifier(pollComposerEl, 'poll-composer')
                if (pollController) {
                    pollController.removePoll()
                }
            }

            // Reset image dropzone via its Stimulus controller
            const dropzoneEl = modal.querySelector('[data-controller="image-dropzone"]')
            if (dropzoneEl) {
                const dropzoneController = this.application.getControllerForElementAndIdentifier(dropzoneEl, 'image-dropzone')
                if (dropzoneController) {
                    dropzoneController.close()
                }
            }

            // Reset submit button text
            const submitButton = modal.querySelector('[data-compose-message-target="submitButton"]')
            if (submitButton) {
                submitButton.textContent = 'Send Message'
                submitButton.disabled = false
            }

            // Reset values
            this.recipientTypeValue = ''
            this.recipientIdValue = null
            this.recipientNameValue = ''
            this.recipientHeadshotValue = ''
            this.recipientInitialsValue = ''
            this.castMembersValue = []
            this.batchPersonIdsValue = []
            this.productionIdValue = null

            // Reset sender identity to production_team (but keep section visible)
            const senderIdentitySection = modal.querySelector('[data-compose-message-target="senderIdentitySection"]')
            if (senderIdentitySection) {
                const hiddenInput = senderIdentitySection.querySelector('input[name="sender_identity"]')
                if (hiddenInput) hiddenInput.value = 'production_team'
                const label = senderIdentitySection.querySelector('[data-compose-message-target="senderIdentityLabel"]')
                const hint = senderIdentitySection.querySelector('[data-compose-message-target="senderIdentityHint"]')
                if (label) label.textContent = 'Production Team'
                if (hint) hint.textContent = '(visible to all team members)'
            }
        }
    }

    closeOnBackdrop(event) {
        if (event.target === event.currentTarget) {
            this.close()
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    closeDropdowns(event) {
        // Close any open dropdowns in the modal when clicking elsewhere
        // But not if clicking on the dropdown button itself
        const modal = this.hasModalTarget ? this.modalTarget : document.getElementById('compose-message-modal')
        if (!modal) return

        const dropdowns = modal.querySelectorAll('[data-controller="dropdown"]')
        dropdowns.forEach(dropdown => {
            if (!dropdown.contains(event.target)) {
                const menu = dropdown.querySelector('[data-dropdown-target="menu"]')
                if (menu) menu.classList.add('hidden')
            }
        })
    }

    selectSenderIdentity(event) {
        event.preventDefault()
        const value = event.currentTarget.dataset.value
        const modal = this.hasModalTarget ? this.modalTarget : document.getElementById('compose-message-modal')

        // Update hidden input
        const hiddenInput = modal.querySelector('input[name="sender_identity"]')
        if (hiddenInput) hiddenInput.value = value

        // Update button display
        const label = modal.querySelector('[data-compose-message-target="senderIdentityLabel"]')
        const hint = modal.querySelector('[data-compose-message-target="senderIdentityHint"]')
        const button = modal.querySelector('[data-compose-message-target="senderIdentityButton"]')
        const iconContainer = button?.querySelector('div:first-child > div:first-child')

        if (value === 'production_team') {
            if (label) label.textContent = 'Production Team'
            if (hint) hint.textContent = '(visible to all team members)'
            if (iconContainer) {
                iconContainer.classList.remove('bg-gray-400')
                iconContainer.classList.add('bg-pink-500')
                iconContainer.innerHTML = `<svg class="w-3.5 h-3.5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z" />
                </svg>`
            }
        } else {
            if (label) label.textContent = 'Just Me'
            if (hint) hint.textContent = '(private conversation)'
            if (iconContainer) {
                iconContainer.classList.remove('bg-pink-500')
                iconContainer.classList.add('bg-gray-400')
                iconContainer.innerHTML = `<svg class="w-3.5 h-3.5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                </svg>`
            }
        }

        // Close dropdown by clicking elsewhere
        document.body.click()
    }

    async submit(event) {
        event.preventDefault()
        event.stopPropagation()
        event.stopImmediatePropagation()

        const modal = this.hasModalTarget ? this.modalTarget : document.getElementById('compose-message-modal')
        const form = modal?.querySelector('[data-compose-message-target="form"]')
        const submitButton = modal?.querySelector('[data-compose-message-target="submitButton"]')

        if (!form) return

        // Disable button while submitting
        if (submitButton) {
            submitButton.disabled = true
            submitButton.textContent = 'Sending...'
        }

        try {
            const formData = new FormData(form)

            // Get files from image-dropzone controller if present
            const dropzoneElement = form.querySelector('[data-controller="image-dropzone"]')
            if (dropzoneElement) {
                const dropzoneController = this.application.getControllerForElementAndIdentifier(dropzoneElement, 'image-dropzone')
                if (dropzoneController && dropzoneController.files && dropzoneController.files.length > 0) {
                    // Remove any empty images entries and add our files
                    formData.delete('images[]')
                    dropzoneController.files.forEach(file => {
                        formData.append('images[]', file)
                    })
                }
            }

            const response = await fetch(form.action, {
                method: 'POST',
                body: formData,
                headers: {
                    'Accept': 'text/html, application/xhtml+xml'
                }
            })

            if (response.ok) {
                this.close()
                // Set cookie for notice since flash is consumed by fetch
                document.cookie = 'flash_notice=Message sent successfully; path=/; max-age=10'
                // Handle redirect
                if (response.redirected) {
                    window.location.href = response.url
                } else {
                    window.location.href = '/manage/messages'
                }
            } else {
                console.error('Failed to send message:', response.status)
                // Reset button on error
                if (submitButton) {
                    submitButton.disabled = false
                    submitButton.textContent = 'Send Message'
                }
            }
        } catch (error) {
            console.error('Error sending message:', error)
            if (submitButton) {
                submitButton.disabled = false
                submitButton.textContent = 'Send Message'
            }
        }
    }

    // Convert simple markdown to HTML for Trix editor
    markdownToHtml(text) {
        if (!text) return ''

        return text
            // Convert **bold** to <strong>
            .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
            // Convert *italic* to <em>
            .replace(/\*(.+?)\*/g, '<em>$1</em>')
            // Convert [text](url) to <a href="url">text</a>
            .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>')
            // Convert double newlines to paragraph breaks
            .split(/\n\n+/)
            .map(p => `<div>${p.replace(/\n/g, '<br>')}</div>`)
            .join('')
    }
}
