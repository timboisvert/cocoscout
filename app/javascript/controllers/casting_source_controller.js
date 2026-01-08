import { Controller } from "@hotwired/stimulus"

// Controls the casting source selection and dynamic tab visibility
export default class extends Controller {
    static targets = ["radio", "option", "talentPoolTab", "talentPoolPanel"]
    static values = {
        updateUrl: String
    }

    connect() {
        this.submitting = false
        // Update UI to match current selection
        this.updateOptionStyles()
    }

    select(event) {
        const selectedValue = event.target.value

        // Update visual styling immediately
        this.updateOptionStyles()

        // Show/hide talent pool tab based on selection
        this.updateTalentPoolVisibility(selectedValue)

        // Auto-save to server
        this.saveSelection(selectedValue)
    }

    updateOptionStyles() {
        this.optionTargets.forEach(option => {
            const radio = option.querySelector('input[type="radio"]')
            if (radio && radio.checked) {
                option.classList.remove('border-gray-200')
                option.classList.add('border-pink-500', 'bg-pink-50')
            } else {
                option.classList.remove('border-pink-500', 'bg-pink-50')
                option.classList.add('border-gray-200')
            }
        })
    }

    updateTalentPoolVisibility(selectedValue) {
        const showTalentPool = selectedValue === 'talent_pool' || selectedValue === 'hybrid'

        if (this.hasTalentPoolTabTarget) {
            if (showTalentPool) {
                this.talentPoolTabTarget.classList.remove('hidden')
            } else {
                this.talentPoolTabTarget.classList.add('hidden')

                // If we're currently on the talent pool tab (index 2), switch to first tab
                const currentHash = window.location.hash
                if (currentHash === '#tab-2') {
                    // Find the tabs controller on the same element and call show(0)
                    const tabsController = this.application.getControllerForElementAndIdentifier(this.element, 'tabs')
                    if (tabsController) {
                        tabsController.show(0)
                        history.replaceState(null, '', '#tab-0')
                    }
                }
            }
        }

        if (this.hasTalentPoolPanelTarget) {
            if (!showTalentPool) {
                this.talentPoolPanelTarget.classList.add('hidden')
            }
        }
    }

    async saveSelection(value) {
        if (this.submitting) return
        this.submitting = true

        try {
            const formData = new FormData()
            formData.append('production[casting_source]', value)
            formData.append('_method', 'patch')

            const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

            const response = await fetch(this.updateUrlValue, {
                method: 'POST',
                headers: {
                    'X-CSRF-Token': csrfToken,
                    'Accept': 'text/vnd.turbo-stream.html, text/html, application/xhtml+xml'
                },
                body: formData
            })

            if (response.ok) {
                this.showNotice('Casting source saved')
            } else {
                console.error('Failed to save casting source')
                this.showError('Failed to save casting source')
            }
        } catch (error) {
            console.error('Error saving casting source:', error)
            this.showError('Failed to save casting source')
        } finally {
            this.submitting = false
        }
    }

    showNotice(message) {
        const flash = document.createElement('div')
        flash.className = 'fixed top-4 right-4 z-50 bg-green-500 text-white px-4 py-3 rounded-lg shadow-lg transition-opacity duration-300'
        flash.textContent = message
        document.body.appendChild(flash)

        setTimeout(() => {
            flash.classList.add('opacity-0')
            setTimeout(() => flash.remove(), 300)
        }, 3000)
    }

    showError(message) {
        const flash = document.createElement('div')
        flash.className = 'fixed top-4 right-4 z-50 bg-red-500 text-white px-4 py-3 rounded-lg shadow-lg transition-opacity duration-300'
        flash.textContent = message
        document.body.appendChild(flash)

        setTimeout(() => {
            flash.classList.add('opacity-0')
            setTimeout(() => flash.remove(), 300)
        }, 3000)
    }
}
