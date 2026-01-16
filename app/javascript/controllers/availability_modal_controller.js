import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "content", "memberModal", "memberContent"]
    static values = { productionId: Number }

    connect() {
        // Bind escape key handler
        this.handleEscape = (event) => {
            if (event.key === 'Escape') {
                this.closeModal()
                this.closeMemberModal()
            }
        }
    }

    // Open modal for a specific show
    async openShowModal(event) {
        event.preventDefault()
        const modalUrl = event.currentTarget.dataset.modalUrl

        if (!modalUrl) {
            console.error('No modal URL provided')
            return
        }

        // Show modal with loading state
        this.modalTarget.classList.remove('hidden')
        document.body.classList.add('overflow-hidden')

        try {
            const response = await fetch(modalUrl, {
                headers: {
                    'Accept': 'text/html',
                    'X-Requested-With': 'XMLHttpRequest'
                }
            })

            if (!response.ok) {
                throw new Error('Failed to load availability')
            }

            const html = await response.text()
            this.contentTarget.innerHTML = html
        } catch (error) {
            console.error('Error loading availability:', error)
            this.contentTarget.innerHTML = `
                <div class="p-8 text-center">
                    <svg class="w-12 h-12 mx-auto mb-3 text-red-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
                    </svg>
                    <p class="text-red-600">Failed to load availability. Please try again.</p>
                    <button type="button" class="mt-4 px-4 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200" data-action="click->availability-modal#closeModal">Close</button>
                </div>
            `
        }
    }

    // Open modal for a specific person/group
    async openMemberModal(event) {
        event.preventDefault()
        const memberType = event.currentTarget.dataset.memberType
        const memberId = event.currentTarget.dataset.memberId
        const memberName = event.currentTarget.dataset.memberName

        // Build URL based on member type
        let modalUrl
        if (memberType === 'Person') {
            modalUrl = `/manage/people/${memberId}/availability_modal`
        } else {
            modalUrl = `/manage/groups/${memberId}/availability_modal`
        }

        // Add production_id if available to select the right tab
        if (this.hasProductionIdValue && this.productionIdValue) {
            modalUrl += `?production_id=${this.productionIdValue}`
        }

        // Show modal with loading state
        this.memberModalTarget.classList.remove('hidden')
        document.body.classList.add('overflow-hidden')

        try {
            const response = await fetch(modalUrl, {
                headers: {
                    'Accept': 'text/html',
                    'X-Requested-With': 'XMLHttpRequest'
                }
            })

            if (!response.ok) {
                throw new Error('Failed to load availability')
            }

            const html = await response.text()
            this.memberContentTarget.innerHTML = html
        } catch (error) {
            console.error('Error loading member availability:', error)
            this.memberContentTarget.innerHTML = `
                <div class="p-8 text-center">
                    <svg class="w-12 h-12 mx-auto mb-3 text-red-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
                    </svg>
                    <p class="text-red-600">Failed to load availability for ${memberName}. Please try again.</p>
                    <button type="button" class="mt-4 px-4 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200" data-action="click->availability-modal#closeMemberModal">Close</button>
                </div>
            `
        }
    }

    closeModal() {
        if (this.hasModalTarget) {
            this.modalTarget.classList.add('hidden')
            document.body.classList.remove('overflow-hidden')
            // Reset content to loading state for next time
            this.contentTarget.innerHTML = `
                <div class="p-8 text-center">
                    <div class="animate-spin w-8 h-8 border-2 border-pink-500 border-t-transparent rounded-full mx-auto"></div>
                    <p class="text-sm text-gray-500 mt-2">Loading...</p>
                </div>
            `
            // Dispatch event to refresh the grid
            document.dispatchEvent(new CustomEvent('availability-grid:refresh'))
        }
    }

    closeMemberModal() {
        if (this.hasMemberModalTarget) {
            this.memberModalTarget.classList.add('hidden')
            document.body.classList.remove('overflow-hidden')
            // Reset content to loading state for next time
            this.memberContentTarget.innerHTML = `
                <div class="p-8 text-center">
                    <div class="animate-spin w-8 h-8 border-2 border-pink-500 border-t-transparent rounded-full mx-auto"></div>
                    <p class="text-sm text-gray-500 mt-2">Loading...</p>
                </div>
            `
            // Dispatch event to refresh the grid
            document.dispatchEvent(new CustomEvent('availability-grid:refresh'))
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }
}
