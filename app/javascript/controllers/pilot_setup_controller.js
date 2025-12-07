import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        // Talent targets
        "talentUserModal", "talentUserForm", "talentUserErrors", "talentUserInfo", "talentUserButton", "talentUserCard",
        "talentSuccess", "talentSuccessMessage",

        // Producer targets
        "producerUserModal", "producerUserForm", "producerUserErrors", "producerUserInfo", "producerUserButton", "producerUserCard", "producerUserResendLink",
        "producerOrgModal", "producerOrgForm", "producerOrgErrors", "producerOrgInfo", "producerOrgButton", "producerOrgCard",
        "producerLocationModal", "producerLocationForm", "producerLocationErrors", "producerLocationInfo", "producerLocationButton", "producerLocationCard",
        "producerProductionModal", "producerProductionForm", "producerProductionErrors", "producerProductionInfo", "producerProductionButton", "producerProductionCard",
        "producerTalentPoolModal", "producerTalentPoolForm", "producerTalentPoolErrors", "producerTalentPoolInfo", "producerTalentPoolButton", "producerTalentPoolCard",
        "producerShowModal", "producerShowForm", "producerShowErrors", "producerShowInfo", "producerShowButton", "producerShowCard",
        "producerAdditionalModal", "producerAdditionalForm", "producerAdditionalErrors", "producerAdditionalInfo", "producerAdditionalButton", "producerAdditionalCard",
        "producerSuccess",

        // Complete Setup Modal targets
        "completeSetupModal", "completeSetupUser", "completeSetupOrg", "completeSetupLocation", "completeSetupProduction", "completeSetupTalentPool", "completeSetupAdditional", "completeSetupAdditionalSection"
    ]

    static values = {
        talentState: Object,
        producerState: Object
    }

    connect() {
        // Initialize producer state
        this.producerState = {
            userId: null,
            personId: null,
            orgId: null,
            locationId: null,
            productionId: null,
            talentPoolId: null,
            roleId: null,
            showId: null
        }

        // Restore from session if available
        this.restoreState()
    }

    restoreState() {
        // Restore talent state
        if (this.talentStateValue && this.talentStateValue.completed) {
            this.talentUserInfoTarget.textContent = `${this.talentStateValue.name} (${this.talentStateValue.email})`
            this.talentUserButtonTarget.textContent = 'Created ✓'
            this.talentUserButtonTarget.classList.remove('bg-pink-500', 'hover:bg-pink-600')
            this.talentUserButtonTarget.classList.add('bg-green-500')
            this.talentSuccessTarget.classList.remove('hidden')
            this.talentSuccessMessageTarget.textContent = `Created talent for ${this.talentStateValue.name} (${this.talentStateValue.email})`
        }

        // Restore producer state
        if (this.producerStateValue && Object.keys(this.producerStateValue).length > 0) {
            const state = this.producerStateValue

            // Restore user_id to component state
            if (state.user_id) {
                this.producerState.userId = state.user_id
                this.producerState.personId = state.person_id

                this.producerUserInfoTarget.textContent = `${state.name} (${state.email})`
                this.producerUserButtonTarget.textContent = 'Created ✓'
                this.producerUserButtonTarget.classList.remove('bg-pink-500', 'hover:bg-pink-600')
                this.producerUserButtonTarget.classList.add('bg-green-500')
                if (this.hasProducerUserResendLinkTarget) {
                    this.producerUserResendLinkTarget.classList.remove('hidden')
                }
                this.enableStep(2)
            }

            if (state.organization_id) {
                this.producerState.orgId = state.organization_id

                this.producerOrgInfoTarget.textContent = state.organization_name
                this.producerOrgButtonTarget.textContent = 'Created ✓'
                this.producerOrgButtonTarget.classList.remove('bg-pink-500', 'hover:bg-pink-600')
                this.producerOrgButtonTarget.classList.add('bg-green-500')
                this.enableStep(3)
            }

            if (state.location_id) {
                this.producerState.locationId = state.location_id

                this.producerLocationInfoTarget.textContent = state.location_name
                this.producerLocationButtonTarget.textContent = 'Created ✓'
                this.producerLocationButtonTarget.classList.remove('bg-pink-500', 'hover:bg-pink-600')
                this.producerLocationButtonTarget.classList.add('bg-green-500')
                this.enableStep(4)
            }

            if (state.production_id) {
                this.producerState.productionId = state.production_id

                this.producerProductionInfoTarget.textContent = state.production_name ? `Production: ${state.production_name}` : 'Production created'
                this.producerProductionButtonTarget.textContent = 'Created ✓'
                this.producerProductionButtonTarget.classList.remove('bg-pink-500', 'hover:bg-pink-600')
                this.producerProductionButtonTarget.classList.add('bg-green-500')
                this.enableStep(5)
            }

            if (state.talent_pool_id) {
                this.producerState.talentPoolId = state.talent_pool_id
                this.producerState.roleId = state.role_id

                const talentPoolText = state.talent_pool_name && state.role_name
                    ? `Pool: ${state.talent_pool_name}, Role: ${state.role_name}`
                    : 'Talent pool created'
                this.producerTalentPoolInfoTarget.textContent = talentPoolText
                this.producerTalentPoolButtonTarget.textContent = 'Created ✓'
                this.producerTalentPoolButtonTarget.classList.remove('bg-pink-500', 'hover:bg-pink-600')
                this.producerTalentPoolButtonTarget.classList.add('bg-green-500')
                this.enableStep(6)

                // Show success banner only if all steps 1-5 are completed
                if (state.user_id && state.organization_id && state.location_id && state.production_id && state.talent_pool_id) {
                    this.producerSuccessTarget.classList.remove('hidden')
                }
            }

            // Restore additional producers if any
            if (state.additional_producers && state.additional_producers.length > 0) {
                this.producerAdditionalInfoTarget.textContent = `Added: ${state.additional_producers.join(', ')}`
            }
        }
    }

    // ==== TALENT SETUP ====
    openTalentUserModal(event) {
        event.preventDefault()
        this.talentUserModalTarget.classList.remove('hidden')
        this.talentUserFormTarget.reset()
        this.talentUserErrorsTarget.classList.add('hidden')
    }

    closeTalentUserModal(event) {
        if (event) event.preventDefault()
        this.talentUserModalTarget.classList.add('hidden')
    }

    async submitTalentUser(event) {
        event.preventDefault()

        const formData = new FormData(this.talentUserFormTarget)
        const data = Object.fromEntries(formData.entries())

        try {
            const response = await fetch('/pilot/create_talent', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
                },
                body: JSON.stringify(data)
            })

            const result = await response.json()

            if (result.success) {
                this.closeTalentUserModal()

                // Update UI
                this.talentUserInfoTarget.textContent = `${result.person.name} (${result.user.email})`
                this.talentUserButtonTarget.textContent = 'Created ✓'
                this.talentUserButtonTarget.classList.remove('bg-pink-500', 'hover:bg-pink-600')
                this.talentUserButtonTarget.classList.add('bg-green-500')

                // Show success message
                this.talentSuccessTarget.classList.remove('hidden')
                this.talentSuccessMessageTarget.textContent = `Created talent for ${result.person.name} (${result.user.email})`
            } else {
                this.talentUserErrorsTarget.classList.remove('hidden')
                this.talentUserErrorsTarget.querySelector('p').textContent = result.errors.join(', ')
            }
        } catch (error) {
            this.talentUserErrorsTarget.classList.remove('hidden')
            this.talentUserErrorsTarget.querySelector('p').textContent = 'An error occurred. Please try again.'
        }
    }

    resetTalentSetup(event) {
        event.preventDefault()

        // Reset UI
        this.talentUserInfoTarget.textContent = 'Click "Create User" to set up the user account'
        this.talentUserButtonTarget.textContent = 'Create User'
        this.talentUserButtonTarget.disabled = false
        this.talentUserButtonTarget.classList.add('bg-pink-500', 'hover:bg-pink-600')
        this.talentUserButtonTarget.classList.remove('bg-green-500')

        // Hide success
        this.talentSuccessTarget.classList.add('hidden')

        // Reset form
        this.talentUserFormTarget.reset()
    }

    // ==== PRODUCER SETUP - STEP 1: USER ====
    openProducerUserModal(event) {
        event.preventDefault()
        if (this.producerUserButtonTarget.textContent.includes('✓')) return
        this.producerUserModalTarget.classList.remove('hidden')
        this.producerUserFormTarget.reset()
        this.producerUserErrorsTarget.classList.add('hidden')
    }

    closeProducerUserModal(event) {
        if (event) event.preventDefault()
        this.producerUserModalTarget.classList.add('hidden')
    }

    async submitProducerUser(event) {
        event.preventDefault()

        const formData = new FormData(this.producerUserFormTarget)
        const data = Object.fromEntries(formData.entries())

        try {
            const response = await fetch('/pilot/create_producer_user', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
                },
                body: JSON.stringify(data)
            })

            const result = await response.json()

            if (result.success) {
                this.closeProducerUserModal()

                // Store IDs
                this.producerState.userId = result.user.id
                this.producerState.personId = result.person.id

                // Update step 1 UI
                this.producerUserInfoTarget.textContent = `${result.person.name} (${result.user.email})`
                this.producerUserButtonTarget.textContent = 'Created ✓'
                this.producerUserButtonTarget.classList.remove('bg-pink-500', 'hover:bg-pink-600')
                this.producerUserButtonTarget.classList.add('bg-green-500')

                // Show resend link
                if (this.hasProducerUserResendLinkTarget) {
                    this.producerUserResendLinkTarget.classList.remove('hidden')
                }

                // Enable step 2
                this.enableStep(2)
            } else {
                this.producerUserErrorsTarget.classList.remove('hidden')
                this.producerUserErrorsTarget.querySelector('p').textContent = result.errors.join(', ')
            }
        } catch (error) {
            this.producerUserErrorsTarget.classList.remove('hidden')
            this.producerUserErrorsTarget.querySelector('p').textContent = 'An error occurred. Please try again.'
        }
    }

    async resendProducerUserInvitation(event) {
        event.preventDefault()

        try {
            const response = await fetch('/pilot/resend_invitation', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
                },
                body: JSON.stringify({
                    user_id: this.producerState.userId,
                    organization_id: this.producerState.orgId || null
                })
            })

            const result = await response.json()

            if (result.success) {
                // Show brief success feedback
                const originalText = this.producerUserResendLinkTarget.textContent
                this.producerUserResendLinkTarget.textContent = '✓ Invitation Sent!'
                setTimeout(() => {
                    this.producerUserResendLinkTarget.textContent = originalText
                }, 2000)
            }
        } catch (error) {
            console.error('Error resending invitation:', error)
        }
    }

    // ==== PRODUCER SETUP - STEP 2: ORGANIZATION ====
    openProducerOrgModal(event) {
        event.preventDefault()
        if (this.producerOrgButtonTarget.textContent.includes('✓')) return
        this.producerOrgModalTarget.classList.remove('hidden')
        this.producerOrgFormTarget.reset()
        this.producerOrgErrorsTarget.classList.add('hidden')
    }

    closeProducerOrgModal(event) {
        if (event) event.preventDefault()
        this.producerOrgModalTarget.classList.add('hidden')
    }

    async submitProducerOrg(event) {
        event.preventDefault()

        const formData = new FormData(this.producerOrgFormTarget)
        const data = {
            user_id: this.producerState.userId,
            organization_name: formData.get('organization_name')
        }

        try {
            const response = await fetch('/pilot/create_producer_org', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
                },
                body: JSON.stringify(data)
            })

            const result = await response.json()

            if (result.success) {
                this.closeProducerOrgModal()

                // Store IDs
                this.producerState.orgId = result.organization.id

                // Update step 2 UI
                this.producerOrgInfoTarget.textContent = result.organization.name
                this.producerOrgButtonTarget.textContent = 'Created ✓'
                this.producerOrgButtonTarget.classList.remove('bg-pink-500', 'hover:bg-pink-600')
                this.producerOrgButtonTarget.classList.add('bg-green-500')

                // Enable step 3
                this.enableStep(3)
            } else {
                this.producerOrgErrorsTarget.classList.remove('hidden')
                this.producerOrgErrorsTarget.querySelector('p').textContent = result.errors.join(', ')
            }
        } catch (error) {
            this.producerOrgErrorsTarget.classList.remove('hidden')
            this.producerOrgErrorsTarget.querySelector('p').textContent = 'An error occurred. Please try again.'
        }
    }

    // ==== PRODUCER SETUP - STEP 3: LOCATION ====
    openProducerLocationModal(event) {
        event.preventDefault()
        if (this.producerLocationButtonTarget.textContent.includes('✓')) return
        this.producerLocationModalTarget.classList.remove('hidden')
        this.producerLocationFormTarget.reset()
        this.producerLocationErrorsTarget.classList.add('hidden')
    }

    closeProducerLocationModal(event) {
        if (event) event.preventDefault()
        this.producerLocationModalTarget.classList.add('hidden')
    }

    async submitProducerLocation(event) {
        event.preventDefault()

        const formData = new FormData(this.producerLocationFormTarget)
        const data = {
            organization_id: this.producerState.orgId,
            location_name: formData.get('location_name'),
            address1: formData.get('address1'),
            address2: formData.get('address2'),
            city: formData.get('city'),
            state: formData.get('state'),
            postal_code: formData.get('postal_code')
        }

        try {
            const response = await fetch('/pilot/create_producer_location', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
                },
                body: JSON.stringify(data)
            })

            const result = await response.json()

            if (result.success) {
                this.closeProducerLocationModal()

                // Store IDs
                this.producerState.locationId = result.location.id

                // Update step 3 UI
                this.producerLocationInfoTarget.textContent = result.location.name
                this.producerLocationButtonTarget.textContent = 'Created ✓'
                this.producerLocationButtonTarget.classList.remove('bg-pink-500', 'hover:bg-pink-600')
                this.producerLocationButtonTarget.classList.add('bg-green-500')

                // Enable step 4
                this.enableStep(4)
            } else {
                this.producerLocationErrorsTarget.classList.remove('hidden')
                this.producerLocationErrorsTarget.querySelector('p').textContent = result.errors.join(', ')
            }
        } catch (error) {
            this.producerLocationErrorsTarget.classList.remove('hidden')
            this.producerLocationErrorsTarget.querySelector('p').textContent = 'An error occurred. Please try again.'
        }
    }

    // ==== PRODUCER SETUP - STEP 4: PRODUCTION ====
    openProducerProductionModal(event) {
        event.preventDefault()
        if (this.producerProductionButtonTarget.textContent.includes('✓')) return
        this.producerProductionModalTarget.classList.remove('hidden')
        this.producerProductionFormTarget.reset()
        this.producerProductionErrorsTarget.classList.add('hidden')
    }

    closeProducerProductionModal(event) {
        if (event) event.preventDefault()
        this.producerProductionModalTarget.classList.add('hidden')
    }

    async submitProducerProduction(event) {
        event.preventDefault()

        const formData = new FormData(this.producerProductionFormTarget)
        const data = {
            organization_id: this.producerState.orgId,
            production_name: formData.get('production_name')
        }

        try {
            const response = await fetch('/pilot/create_producer_production', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
                },
                body: JSON.stringify(data)
            })

            const result = await response.json()

            if (result.success) {
                this.closeProducerProductionModal()

                // Store ID
                this.producerState.productionId = result.production.id

                // Update step 4 UI
                this.producerProductionInfoTarget.textContent = `Production: ${result.production.name}`
                this.producerProductionButtonTarget.textContent = 'Created ✓'
                this.producerProductionButtonTarget.classList.remove('bg-pink-500', 'hover:bg-pink-600')
                this.producerProductionButtonTarget.classList.add('bg-green-500')

                // Enable step 5 (Talent Pool)
                this.enableStep(5)
            } else {
                this.producerProductionErrorsTarget.classList.remove('hidden')
                this.producerProductionErrorsTarget.querySelector('p').textContent = result.errors.join(', ')
            }
        } catch (error) {
            this.producerProductionErrorsTarget.classList.remove('hidden')
            this.producerProductionErrorsTarget.querySelector('p').textContent = 'An error occurred. Please try again.'
        }
    }

    // ==== PRODUCER SETUP - STEP 5: TALENT POOL ====
    openProducerTalentPoolModal(event) {
        event.preventDefault()
        if (this.producerTalentPoolButtonTarget.textContent.includes('✓')) return
        this.producerTalentPoolModalTarget.classList.remove('hidden')
        this.producerTalentPoolFormTarget.reset()
        this.producerTalentPoolErrorsTarget.classList.add('hidden')
    }

    closeProducerTalentPoolModal(event) {
        if (event) event.preventDefault()
        this.producerTalentPoolModalTarget.classList.add('hidden')
    }

    async submitProducerTalentPool(event) {
        event.preventDefault()

        const formData = new FormData(this.producerTalentPoolFormTarget)
        const data = {
            production_id: this.producerState.productionId,
            talent_pool_name: formData.get('talent_pool_name'),
            role_name: formData.get('role_name')
        }

        try {
            const response = await fetch('/pilot/create_producer_talent_pool', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
                },
                body: JSON.stringify(data)
            })

            const result = await response.json()

            if (result.success) {
                this.closeProducerTalentPoolModal()

                // Store IDs
                this.producerState.talentPoolId = result.talent_pool.id
                this.producerState.roleId = result.role.id

                // Update step 5 UI
                this.producerTalentPoolInfoTarget.textContent = `Pool: ${result.talent_pool.name}, Role: ${result.role.name}`
                this.producerTalentPoolButtonTarget.textContent = 'Created ✓'
                this.producerTalentPoolButtonTarget.classList.remove('bg-pink-500', 'hover:bg-pink-600')
                this.producerTalentPoolButtonTarget.classList.add('bg-green-500')

                // Enable step 6 (Additional Collaborators) and show success
                this.enableStep(6)
                this.producerSuccessTarget.classList.remove('hidden')
            } else {
                this.producerTalentPoolErrorsTarget.classList.remove('hidden')
                this.producerTalentPoolErrorsTarget.querySelector('p').textContent = result.errors.join(', ')
            }
        } catch (error) {
            this.producerTalentPoolErrorsTarget.classList.remove('hidden')
            this.producerTalentPoolErrorsTarget.querySelector('p').textContent = 'An error occurred. Please try again.'
        }
    }

    // ==== PRODUCER SETUP - STEP 6: SHOW ====
    openProducerShowModal(event) {
        event.preventDefault()
        if (this.producerShowButtonTarget.disabled) return
        this.producerShowModalTarget.classList.remove('hidden')
        this.producerShowFormTarget.reset()
        this.producerShowErrorsTarget.classList.add('hidden')
    }

    closeProducerShowModal(event) {
        if (event) event.preventDefault()
        this.producerShowModalTarget.classList.add('hidden')
    }

    async submitProducerShow(event) {
        event.preventDefault()

        const formData = new FormData(this.producerShowFormTarget)
        const data = {
            production_id: this.producerState.productionId,
            location_id: this.producerState.locationId,
            show_name: formData.get('show_name'),
            show_date_time: formData.get('show_date_time')
        }

        try {
            const response = await fetch('/pilot/create_producer_show', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
                },
                body: JSON.stringify(data)
            })

            const result = await response.json()

            if (result.success) {
                this.closeProducerShowModal()

                // Store ID
                this.producerState.showId = result.show.id

                // Update step 5 UI
                this.producerShowInfoTarget.textContent = result.show.name
                this.producerShowButtonTarget.textContent = 'Created ✓'
                this.producerShowButtonTarget.disabled = true
                this.producerShowButtonTarget.classList.remove('bg-pink-500', 'hover:bg-pink-600')
                this.producerShowButtonTarget.classList.add('bg-green-500')

                // Enable step 6 and show success
                this.enableStep(6)
                this.producerSuccessTarget.classList.remove('hidden')
            } else {
                this.producerShowErrorsTarget.classList.remove('hidden')
                this.producerShowErrorsTarget.querySelector('p').textContent = result.errors.join(', ')
            }
        } catch (error) {
            this.producerShowErrorsTarget.classList.remove('hidden')
            this.producerShowErrorsTarget.querySelector('p').textContent = 'An error occurred. Please try again.'
        }
    }

    // ==== PRODUCER SETUP - STEP 6: ADDITIONAL PRODUCERS ====
    openProducerAdditionalModal(event) {
        event.preventDefault()
        this.producerAdditionalModalTarget.classList.remove('hidden')
        this.producerAdditionalFormTarget.reset()
        this.producerAdditionalErrorsTarget.classList.add('hidden')
    }

    closeProducerAdditionalModal(event) {
        if (event) event.preventDefault()
        this.producerAdditionalModalTarget.classList.add('hidden')
    }

    async submitProducerAdditional(event) {
        event.preventDefault()

        const formData = new FormData(this.producerAdditionalFormTarget)
        const data = {
            organization_id: this.producerState.orgId,
            email: formData.get('email'),
            first_name: formData.get('first_name'),
            last_name: formData.get('last_name')
        }

        try {
            const response = await fetch('/pilot/create_producer_additional', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
                },
                body: JSON.stringify(data)
            })

            const result = await response.json()

            if (result.success) {
                this.closeProducerAdditionalModal()

                // Update step 5 UI to show success
                const currentInfo = this.producerAdditionalInfoTarget.textContent
                if (currentInfo === 'Complete step 4 first' || currentInfo === 'Click to add initial collaborators, colleagues, or co-producers') {
                    this.producerAdditionalInfoTarget.textContent = `Added: ${result.person.name}`
                } else {
                    this.producerAdditionalInfoTarget.textContent += `, ${result.person.name}`
                }

                // Reset form to allow adding more
                this.producerAdditionalFormTarget.reset()
            } else {
                this.producerAdditionalErrorsTarget.classList.remove('hidden')
                this.producerAdditionalErrorsTarget.querySelector('p').textContent = result.errors.join(', ')
            }
        } catch (error) {
            this.producerAdditionalErrorsTarget.classList.remove('hidden')
            this.producerAdditionalErrorsTarget.querySelector('p').textContent = 'An error occurred. Please try again.'
        }
    }

    // ==== HELPER METHODS ====
    enableStep(step) {
        const cardMap = {
            2: this.producerOrgCardTarget,
            3: this.producerLocationCardTarget,
            4: this.producerProductionCardTarget,
            5: this.producerTalentPoolCardTarget,
            6: this.producerAdditionalCardTarget
        }

        const buttonMap = {
            2: this.producerOrgButtonTarget,
            3: this.producerLocationButtonTarget,
            4: this.producerProductionButtonTarget,
            5: this.producerTalentPoolButtonTarget,
            6: this.producerAdditionalButtonTarget
        }

        const infoMap = {
            2: this.producerOrgInfoTarget,
            3: this.producerLocationInfoTarget,
            4: this.producerProductionInfoTarget,
            5: this.producerTalentPoolInfoTarget,
            6: this.producerAdditionalInfoTarget
        }

        const infoText = {
            2: 'Click "Create Organization" to continue',
            3: 'Click "Create Location" to continue',
            4: 'Click "Create Production" to continue',
            5: 'Click "Create Talent Pool" to continue',
            6: 'Click to add initial collaborators, colleagues, or co-producers'
        }

        if (cardMap[step]) {
            cardMap[step].classList.remove('opacity-50')
            buttonMap[step].classList.remove('disabled:opacity-50')
            infoMap[step].textContent = infoText[step]
        }
    }

    resetProducerSetup(event) {
        event.preventDefault()

        // Reset state
        this.producerState = {
            userId: null,
            personId: null,
            orgId: null,
            locationId: null,
            productionId: null,
            showId: null
        }

        // Reset all steps
        const steps = [
            { card: this.producerUserCardTarget, button: this.producerUserButtonTarget, info: this.producerUserInfoTarget, text: 'Click "Create User" to start' },
            { card: this.producerOrgCardTarget, button: this.producerOrgButtonTarget, info: this.producerOrgInfoTarget, text: 'Complete step 1 first' },
            { card: this.producerLocationCardTarget, button: this.producerLocationButtonTarget, info: this.producerLocationInfoTarget, text: 'Complete step 2 first' },
            { card: this.producerShowCardTarget, button: this.producerShowButtonTarget, info: this.producerShowInfoTarget, text: 'Complete step 3 first' },
            { card: this.producerAdditionalCardTarget, button: this.producerAdditionalButtonTarget, info: this.producerAdditionalInfoTarget, text: 'Complete step 4 first' }
        ]

        steps.forEach((step, index) => {
            if (index === 0) {
                step.card.classList.remove('opacity-50')
                step.button.disabled = false
                step.button.textContent = 'Create User'
                step.button.classList.remove('bg-green-500')
                step.button.classList.add('bg-pink-500', 'hover:bg-pink-600')
            } else {
                step.card.classList.add('opacity-50')
                step.button.disabled = true
                step.button.classList.remove('bg-pink-500', 'hover:bg-pink-600', 'bg-green-500')
                step.button.classList.add('bg-gray-300', 'text-gray-500', 'cursor-not-allowed')
                step.button.textContent = step.button.textContent.replace('Created ✓', step.button.textContent.includes('Organization') ? 'Create Organization' : step.button.textContent.includes('Location') ? 'Create Location' : step.button.textContent.includes('Show') ? 'Create Show' : 'Add Producer')
            }
            step.info.textContent = step.text
        })

        // Hide success
        this.producerSuccessTarget.classList.add('hidden')

        // Reset all forms
        this.producerUserFormTarget.reset()
        this.producerOrgFormTarget.reset()
        this.producerLocationFormTarget.reset()
        this.producerShowFormTarget.reset()
        this.producerAdditionalFormTarget.reset()
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    // ==== COMPLETE SETUP MODAL ====
    openCompleteSetupModal(event) {
        event.preventDefault()

        // Populate the summary with current state
        const state = this.producerStateValue

        // User info
        if (state.name && state.email) {
            this.completeSetupUserTarget.textContent = `${state.name} (${state.email})`
        }

        // Organization info
        if (state.organization_name) {
            this.completeSetupOrgTarget.textContent = state.organization_name
        }

        // Location info
        if (state.location_name) {
            this.completeSetupLocationTarget.textContent = state.location_name
        }

        // Production info
        if (state.production_name) {
            this.completeSetupProductionTarget.textContent = state.production_name
        }

        // Additional producers (if any)
        const additionalInfo = this.producerAdditionalInfoTarget.textContent
        if (additionalInfo && !additionalInfo.includes('Complete step') && !additionalInfo.includes('Click to add')) {
            this.completeSetupAdditionalTarget.textContent = additionalInfo.replace('Added: ', '')
            this.completeSetupAdditionalSectionTarget.classList.remove('hidden')
        } else {
            this.completeSetupAdditionalSectionTarget.classList.add('hidden')
        }

        this.completeSetupModalTarget.classList.remove('hidden')
    }

    closeCompleteSetupModal(event) {
        if (event) event.preventDefault()
        this.completeSetupModalTarget.classList.add('hidden')
    }

    async confirmCompleteSetup(event) {
        event.preventDefault()
        this.closeCompleteSetupModal()

        try {
            // Call the backend to reset the session
            const response = await fetch('/pilot/reset_producer', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
                }
            })

            if (response.ok) {
                // Reload the page to get fresh state
                window.location.reload()
            } else {
                // If backend fails, at least reset the UI
                this.resetProducerSetup(event)
            }
        } catch (error) {
            console.error('Error resetting producer setup:', error)
            // Fallback to UI reset only
            this.resetProducerSetup(event)
        }
    }

    async confirmCompleteTalentSetup(event) {
        event.preventDefault()

        try {
            // Call the backend to reset the session
            const response = await fetch('/pilot/reset_talent', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
                }
            })

            if (response.ok) {
                // Reload the page to get fresh state
                window.location.reload()
            } else {
                // If backend fails, at least reset the UI
                this.resetTalentSetup(event)
            }
        } catch (error) {
            console.error('Error resetting talent setup:', error)
            // Fallback to UI reset only
            this.resetTalentSetup(event)
        }
    }
}
