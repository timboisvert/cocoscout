import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["personModal", "personContent", "showModal", "showContent"]

    connect() {
        // Store current member info for filter switching
        this.currentMemberId = null
        this.currentMemberType = null
        this.currentShowId = null

        // Listen for refresh events from popup controller
        this.element.addEventListener('availability-popup:refresh', this.handlePopupRefresh.bind(this))
    }

    disconnect() {
        this.element.removeEventListener('availability-popup:refresh', this.handlePopupRefresh.bind(this))
    }

    async handlePopupRefresh(event) {
        const { showId, memberId } = event.detail

        // Determine which modal is open and refresh it
        if (this.hasShowModalTarget && !this.showModalTarget.classList.contains('hidden')) {
            await this.refreshShowModal()
        } else if (this.hasPersonModalTarget && !this.personModalTarget.classList.contains('hidden')) {
            await this.refreshPersonModal()
        }
    }

    async refreshShowModal() {
        if (!this.currentShowId) return

        // Store scroll position
        const scrollContainer = this.showContentTarget.querySelector('.overflow-y-auto')
        const scrollTop = scrollContainer?.scrollTop || 0

        try {
            const response = await fetch(`/manage/casting/availability/show_modal/${this.currentShowId}`)
            const html = await response.text()
            this.showContentTarget.innerHTML = html

            // Restore scroll position
            const newScrollContainer = this.showContentTarget.querySelector('.overflow-y-auto')
            if (newScrollContainer) {
                newScrollContainer.scrollTop = scrollTop
            }
        } catch (error) {
            console.error("Error refreshing show modal:", error)
        }
    }

    async refreshPersonModal() {
        if (!this.currentMemberId || !this.currentMemberType) return

        // Store scroll position
        const scrollContainer = this.personContentTarget.querySelector('.overflow-y-auto')
        const scrollTop = scrollContainer?.scrollTop || 0

        try {
            const response = await fetch(`/manage/casting/availability/person_modal/${this.currentMemberId}?type=${this.currentMemberType}`)
            const html = await response.text()
            this.personContentTarget.innerHTML = html

            // Restore scroll position
            const newScrollContainer = this.personContentTarget.querySelector('.overflow-y-auto')
            if (newScrollContainer) {
                newScrollContainer.scrollTop = scrollTop
            }
        } catch (error) {
            console.error("Error refreshing person modal:", error)
        }
    }

    // Person Modal Methods

    async openPersonModal(event) {
        event.stopPropagation()
        const memberType = event.currentTarget.dataset.memberType
        const memberId = event.currentTarget.dataset.memberId

        this.currentMemberId = memberId
        this.currentMemberType = memberType

        this.personModalTarget.classList.remove("hidden")
        document.body.classList.add("overflow-hidden")

        await this.loadPersonModal(memberId, memberType, "date")
    }

    closePersonModal() {
        this.personModalTarget.classList.add("hidden")
        document.body.classList.remove("overflow-hidden")
        this.currentMemberId = null
        this.currentMemberType = null
    }

    async filterPersonByDate(event) {
        event.stopPropagation()
        const memberId = event.currentTarget.dataset.memberId
        const memberType = event.currentTarget.dataset.memberType
        await this.loadPersonModal(memberId, memberType, "date")
    }

    async filterPersonByProduction(event) {
        event.stopPropagation()
        const memberId = event.currentTarget.dataset.memberId
        const memberType = event.currentTarget.dataset.memberType
        await this.loadPersonModal(memberId, memberType, "production")
    }

    async loadPersonModal(memberId, memberType, filterBy) {
        try {
            const response = await fetch(`/manage/casting/availability/person_modal/${memberId}?type=${memberType}&filter_by=${filterBy}`)
            const html = await response.text()
            this.personContentTarget.innerHTML = html
        } catch (error) {
            console.error("Error loading person modal:", error)
            this.personContentTarget.innerHTML = '<div class="p-6 text-center text-red-500">Error loading data</div>'
        }
    }

    // Show Modal Methods

    async openShowModal(event) {
        event.stopPropagation()
        const showId = event.currentTarget.dataset.showId

        this.currentShowId = showId
        this.showModalTarget.classList.remove("hidden")
        document.body.classList.add("overflow-hidden")

        try {
            const response = await fetch(`/manage/casting/availability/show_modal/${showId}`)
            const html = await response.text()
            this.showContentTarget.innerHTML = html
        } catch (error) {
            console.error("Error loading show modal:", error)
            this.showContentTarget.innerHTML = '<div class="p-6 text-center text-red-500">Error loading data</div>'
        }
    }

    closeShowModal() {
        this.showModalTarget.classList.add("hidden")
        document.body.classList.remove("overflow-hidden")
    }

    // Action Methods

    async castPerson(event) {
        event.stopPropagation()
        const showId = event.currentTarget.dataset.showId
        const roleId = event.currentTarget.dataset.roleId
        const personId = event.currentTarget.dataset.personId

        const csrfToken = document.querySelector('meta[name="csrf-token"]').content

        try {
            const response = await fetch("/manage/casting/availability/cast_person", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": csrfToken
                },
                body: JSON.stringify({ show_id: showId, role_id: roleId, person_id: personId })
            })

            const result = await response.json()

            if (result.success) {
                // Reload the page to show updated data
                window.location.reload()
            } else {
                alert(result.error || "Failed to cast person")
            }
        } catch (error) {
            console.error("Error casting person:", error)
            alert("An error occurred")
        }
    }

    async signUpPerson(event) {
        event.stopPropagation()
        const showId = event.currentTarget.dataset.showId
        const personId = event.currentTarget.dataset.personId

        const csrfToken = document.querySelector('meta[name="csrf-token"]').content

        try {
            const response = await fetch("/manage/casting/availability/sign_up_person", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": csrfToken
                },
                body: JSON.stringify({ show_id: showId, person_id: personId })
            })

            const result = await response.json()

            if (result.success) {
                window.location.reload()
            } else {
                alert(result.error || "Failed to sign up person")
            }
        } catch (error) {
            console.error("Error signing up person:", error)
            alert("An error occurred")
        }
    }

    async preRegisterPerson(event) {
        event.stopPropagation()
        const showId = event.currentTarget.dataset.showId
        const personId = event.currentTarget.dataset.personId

        // Confirm pre-registration
        if (!confirm("Pre-register this person? They will be added to the queue and receive a notification email.")) {
            return
        }

        const csrfToken = document.querySelector('meta[name="csrf-token"]').content

        try {
            const response = await fetch("/manage/casting/availability/pre_register", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": csrfToken
                },
                body: JSON.stringify({ show_id: showId, person_id: personId, send_email: true })
            })

            const result = await response.json()

            if (result.success) {
                window.location.reload()
            } else {
                alert(result.error || "Failed to pre-register person")
            }
        } catch (error) {
            console.error("Error pre-registering person:", error)
            alert("An error occurred")
        }
    }

    async preRegisterAll(event) {
        event.stopPropagation()
        const showId = event.currentTarget.dataset.showId
        const personIds = JSON.parse(event.currentTarget.dataset.personIds || '[]')

        if (personIds.length === 0) {
            alert("No people to pre-register")
            return
        }

        const csrfToken = document.querySelector('meta[name="csrf-token"]').content

        // Disable the button and show loading state
        const button = event.currentTarget
        const originalText = button.textContent
        button.disabled = true
        button.textContent = 'Registering...'

        try {
            const response = await fetch("/manage/casting/availability/pre_register_all", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": csrfToken
                },
                body: JSON.stringify({ show_id: showId, person_ids: personIds })
            })

            const result = await response.json()

            if (result.success) {
                // Refresh the modal content instead of reloading the page
                await this.refreshShowModal()
            } else {
                alert(result.error || "Failed to pre-register people")
                button.disabled = false
                button.textContent = originalText
            }
        } catch (error) {
            console.error("Error pre-registering people:", error)
            alert("An error occurred")
            button.disabled = false
            button.textContent = originalText
        }
    }

    // Utility Methods

    stopPropagation(event) {
        event.stopPropagation()
    }
}
