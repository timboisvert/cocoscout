import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "profileSetupModal",
        "entitySelectorModal",
        "profileSection",
        "requestableType",
        "requestableId",
        "dropdownMenu",
        "dropdownChevron",
        "dropdownContainer",
        "profileForm",
        "headshotContainer",
        "headshotPreview",
        "resumeContainer",
        "resumePreview"
    ]

    connect() {
        // Close dropdown when clicking outside
        this.boundCloseDropdown = this.closeDropdownOnClickOutside.bind(this)
    }

    disconnect() {
        document.removeEventListener('click', this.boundCloseDropdown)
    }

    toggleDropdown(event) {
        event.stopPropagation()
        const isHidden = this.dropdownMenuTarget.classList.contains('hidden')

        if (isHidden) {
            this.dropdownMenuTarget.classList.remove('hidden')
            this.dropdownChevronTarget.style.transform = 'rotate(180deg)'
            document.addEventListener('click', this.boundCloseDropdown)
        } else {
            this.closeDropdown()
        }
    }

    closeDropdown() {
        if (this.hasDropdownMenuTarget) {
            this.dropdownMenuTarget.classList.add('hidden')
            if (this.hasDropdownChevronTarget) {
                this.dropdownChevronTarget.style.transform = 'rotate(0deg)'
            }
            document.removeEventListener('click', this.boundCloseDropdown)
        }
    }

    closeDropdownOnClickOutside(event) {
        if (this.hasDropdownContainerTarget && !this.dropdownContainerTarget.contains(event.target)) {
            this.closeDropdown()
        }
    }

    selectPersonFromDropdown(event) {
        event.preventDefault()
        const personId = this.requestableIdTarget.dataset.personId
        this.requestableTypeTarget.value = "Person"
        this.requestableIdTarget.value = personId
        this.closeDropdown()

        // Submit the form to update the session
        const form = document.createElement('form')
        form.method = 'GET'
        form.action = window.location.pathname

        const typeInput = document.createElement('input')
        typeInput.type = 'hidden'
        typeInput.name = 'requestable_type'
        typeInput.value = 'Person'
        form.appendChild(typeInput)

        const idInput = document.createElement('input')
        idInput.type = 'hidden'
        idInput.name = 'requestable_id'
        idInput.value = personId
        form.appendChild(idInput)

        document.body.appendChild(form)
        form.submit()
    }

    selectGroupFromDropdown(event) {
        event.preventDefault()
        const groupId = event.currentTarget.dataset.groupId
        this.requestableTypeTarget.value = "Group"
        this.requestableIdTarget.value = groupId
        this.closeDropdown()

        // Submit the form to update the session
        const form = document.createElement('form')
        form.method = 'GET'
        form.action = window.location.pathname

        const typeInput = document.createElement('input')
        typeInput.type = 'hidden'
        typeInput.name = 'requestable_type'
        typeInput.value = 'Group'
        form.appendChild(typeInput)

        const idInput = document.createElement('input')
        idInput.type = 'hidden'
        idInput.name = 'requestable_id'
        idInput.value = groupId
        form.appendChild(idInput)

        document.body.appendChild(form)
        form.submit()
    }

    openProfileSetup(event) {
        event.preventDefault()
        this.profileSetupModalTarget.classList.remove('hidden')
    }

    closeProfileSetup(event) {
        event.preventDefault()
        this.profileSetupModalTarget.classList.add('hidden')
    }

    async submitProfileForm(event) {
        event.preventDefault()
        const form = this.profileFormTarget
        const formData = new FormData(form)

        try {
            const response = await fetch(form.action, {
                method: form.method,
                body: formData,
                headers: {
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
                }
            })

            if (response.ok || response.redirected) {
                // Close modal and reload page to refresh profile status
                this.profileSetupModalTarget.classList.add('hidden')
                window.location.reload()
            } else {
                // Handle errors - could show them in the modal
                console.error('Profile update failed', response.status)
            }
        } catch (error) {
            console.error('Error submitting profile:', error)
        }
    }

    openEntitySelector(event) {
        event.preventDefault()
        this.entitySelectorModalTarget.classList.remove('hidden')
    }

    closeEntitySelector(event) {
        event.preventDefault()
        this.entitySelectorModalTarget.classList.add('hidden')
    }

    selectPerson(event) {
        event.preventDefault()
        const personId = this.requestableIdTarget.dataset.personId
        this.requestableTypeTarget.value = "Person"
        this.requestableIdTarget.value = personId
        this.closeEntitySelector(event)

        // Reload the page to update the UI
        window.location.reload()
    }

    selectGroup(event) {
        event.preventDefault()
        const groupId = event.currentTarget.dataset.groupId
        this.requestableTypeTarget.value = "Group"
        this.requestableIdTarget.value = groupId
        this.closeEntitySelector(event)

        // Reload the page to update the UI
        window.location.reload()
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    async uploadHeadshot(event) {
        const file = event.target.files[0]
        if (!file) return

        // Show loading state
        this.headshotContainerTarget.innerHTML = `
            <div class="w-full aspect-[3/4] rounded-lg border-2 border-gray-200 bg-gray-50 flex flex-col items-center justify-center">
                <svg class="animate-spin h-12 w-12 text-pink-500 mb-3" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                <p class="text-sm text-gray-600">Uploading...</p>
            </div>
        `

        const formData = new FormData()
        formData.append('person[profile_headshots_attributes][0][image]', file)

        try {
            const response = await fetch('/profile', {
                method: 'PATCH',
                body: formData,
                headers: {
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
                    'Accept': 'application/json'
                }
            })

            const data = await response.json()

            if (data.success && data.headshot) {
                const headshot = data.headshot
                this.headshotContainerTarget.innerHTML = `
                    <div class="relative inline-block" data-audition-request-form-target="headshotPreview">
                        <img src="${headshot.preview_url}" class="w-full aspect-[3/4] rounded-lg object-cover border-2 border-gray-200" />
                        <button type="button"
                                data-action="click->audition-request-form#removeHeadshot"
                                data-headshot-id="${headshot.id}"
                                class="absolute bottom-2 right-2 bg-pink-500 text-white text-xs px-2 py-1 rounded hover:bg-pink-600 cursor-pointer">
                            Remove
                        </button>
                    </div>
                `
            } else {
                console.error('Upload failed:', data)
                this.showHeadshotUploadPrompt()
            }
        } catch (error) {
            console.error('Error uploading headshot:', error)
            this.showHeadshotUploadPrompt()
        }
    }

    showHeadshotUploadPrompt() {
        this.headshotContainerTarget.innerHTML = `
            <label class="block cursor-pointer">
                <input type="file"
                       accept="image/jpeg,image/jpg,image/png"
                       class="hidden"
                       data-action="change->audition-request-form#uploadHeadshot"
                       id="headshot-upload" />
                <div class="w-full aspect-[3/4] border-2 border-dashed border-gray-300 rounded-lg hover:border-pink-400 transition-colors bg-gray-50 hover:bg-pink-50 flex flex-col items-center justify-center">
                    <svg class="w-10 h-10 text-gray-400 mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                    </svg>
                    <p class="text-sm font-medium text-gray-700 text-center px-2">Select a headshot</p>
                    <p class="text-xs text-gray-500 mt-1">JPG, JPEG, or PNG</p>
                </div>
            </label>
        `
    }

    async removeHeadshot(event) {
        event.preventDefault()
        const headshotId = event.currentTarget.dataset.headshotId

        if (!headshotId) return

        const formData = new FormData()
        formData.append('person[profile_headshots_attributes][0][id]', headshotId)
        formData.append('person[profile_headshots_attributes][0][_destroy]', '1')

        try {
            const response = await fetch('/profile', {
                method: 'PATCH',
                body: formData,
                headers: {
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
                    'Accept': 'application/json'
                }
            })

            if (response.ok || response.redirected) {
                this.showHeadshotUploadPrompt()
            }
        } catch (error) {
            console.error('Error removing headshot:', error)
        }
    }

    async uploadResume(event) {
        const file = event.target.files[0]
        if (!file) return

        // Show loading state
        this.resumeContainerTarget.innerHTML = `
            <div class="w-full aspect-[3/4] rounded-lg border-2 border-gray-200 bg-gray-50 flex flex-col items-center justify-center">
                <svg class="animate-spin h-12 w-12 text-pink-500 mb-3" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                <p class="text-sm text-gray-600">Uploading...</p>
            </div>
        `

        const formData = new FormData()
        formData.append('person[profile_resumes_attributes][0][file]', file)

        try {
            const response = await fetch('/profile', {
                method: 'PATCH',
                body: formData,
                headers: {
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
                    'Accept': 'application/json'
                }
            })

            const data = await response.json()

            if (data.success && data.resume) {
                const resume = data.resume
                let previewHTML = ''

                if (resume.preview_url) {
                    // Show the preview image (works for both PDFs and images)
                    previewHTML = `
                        <div class="relative inline-block" data-audition-request-form-target="resumePreview">
                            <img src="${resume.preview_url}" class="w-full aspect-[3/4] rounded-lg object-cover border-2 border-gray-200" />
                            <button type="button"
                                    data-action="click->audition-request-form#removeResume"
                                    data-resume-id="${resume.id}"
                                    class="absolute bottom-2 right-2 bg-pink-500 text-white text-xs px-2 py-1 rounded hover:bg-pink-600 cursor-pointer">
                                Remove
                            </button>
                        </div>
                    `
                } else {
                    // Fallback for PDFs without preview
                    previewHTML = `
                        <div class="relative inline-block" data-audition-request-form-target="resumePreview">
                            <div class="w-full aspect-[3/4] rounded-lg border-2 border-gray-200 bg-gray-50 flex flex-col items-center justify-center p-4">
                                <svg class="w-16 h-16 text-pink-500 mb-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                                </svg>
                                <p class="text-sm font-medium text-gray-900 text-center">PDF Resume</p>
                                <p class="text-xs text-gray-500 mt-1 text-center">${resume.filename}</p>
                            </div>
                            <button type="button"
                                    data-action="click->audition-request-form#removeResume"
                                    data-resume-id="${resume.id}"
                                    class="absolute bottom-2 right-2 bg-pink-500 text-white text-xs px-2 py-1 rounded hover:bg-pink-600 cursor-pointer">
                                Remove
                            </button>
                        </div>
                    `
                }

                this.resumeContainerTarget.innerHTML = previewHTML
            } else {
                console.error('Upload failed:', data)
                this.showResumeUploadPrompt()
            }
        } catch (error) {
            console.error('Error:', error)
            this.showResumeUploadPrompt()
        }
    }

    showResumeUploadPrompt() {
        this.resumeContainerTarget.innerHTML = `
            <label class="block cursor-pointer">
                <input type="file"
                       accept=".pdf,.jpg,.jpeg"
                       class="hidden"
                       data-action="change->audition-request-form#uploadResume"
                       id="resume-upload" />
                <div class="w-full aspect-[3/4] border-2 border-dashed border-gray-300 rounded-lg hover:border-pink-400 transition-colors bg-gray-50 hover:bg-pink-50 flex flex-col items-center justify-center p-4">
                    <svg class="w-10 h-10 text-gray-400 mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                    </svg>
                    <p class="text-sm font-medium text-gray-700 text-center">Select a resume</p>
                    <p class="text-xs text-gray-500 mt-1">PDF, JPG, or JPEG</p>
                </div>
            </label>
        `
    }

    async removeResume(event) {
        event.preventDefault()
        const resumeId = event.currentTarget.dataset.resumeId

        if (!resumeId) return

        const formData = new FormData()
        formData.append('person[profile_resumes_attributes][0][id]', resumeId)
        formData.append('person[profile_resumes_attributes][0][_destroy]', '1')

        try {
            const response = await fetch('/profile', {
                method: 'PATCH',
                body: formData,
                headers: {
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
                    'Accept': 'application/json'
                }
            })

            if (response.ok || response.redirected) {
                this.showResumeUploadPrompt()
            }
        } catch (error) {
            console.error('Error removing resume:', error)
        }
    }
}
