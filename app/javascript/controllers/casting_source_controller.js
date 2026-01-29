import { Controller } from "@hotwired/stimulus"

// Controls the casting source selection
export default class extends Controller {
    static targets = ["radio", "option"]
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

    updateSetting(event) {
        const input = event.target
        const name = input.name
        const value = input.type === 'checkbox' ? (input.checked ? '1' : '0') : input.value
        this.saveSetting(name, value)
    }

    async saveSetting(name, value) {
        if (this.submitting) return
        this.submitting = true

        try {
            const formData = new FormData()
            formData.append(name, value)
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
                this.showNotice('Settings saved')
            } else {
                console.error('Failed to save setting')
                this.showError('Failed to save setting')
            }
        } catch (error) {
            console.error('Error saving setting:', error)
            this.showError('Failed to save setting')
        } finally {
            this.submitting = false
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
        // Remove any existing notices first
        document.querySelectorAll('[data-controller="notice"]').forEach(el => el.remove())

        const flash = document.createElement('div')
        flash.setAttribute('data-controller', 'notice')
        flash.setAttribute('data-notice-timeout-value', '2000')
        flash.setAttribute('data-notice-target', 'container')
        flash.className = 'fixed top-0 left-1/2 transform -translate-x-1/2 z-50 w-auto max-w-lg px-6 py-3 bg-pink-500 text-white shadow-lg flex items-center transition-opacity duration-300 rounded-bl-lg rounded-br-lg'
        flash.innerHTML = `<span class="font-medium">${message}</span>`
        document.body.appendChild(flash)
    }

    showError(message) {
        // Remove any existing notices first
        document.querySelectorAll('[data-controller="notice"]').forEach(el => el.remove())

        const flash = document.createElement('div')
        flash.setAttribute('data-controller', 'notice')
        flash.setAttribute('data-notice-timeout-value', '5000')
        flash.setAttribute('data-notice-target', 'container')
        flash.className = 'fixed top-0 left-1/2 transform -translate-x-1/2 z-50 w-auto max-w-lg px-6 py-3 bg-red-600 text-white shadow-lg flex items-center transition-opacity duration-300 rounded-bl-lg rounded-br-lg'
        flash.innerHTML = `<span class="font-medium">${message}</span>`
        document.body.appendChild(flash)
    }
}
