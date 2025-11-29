import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["platform", "handle", "label", "name", "nameField", "urlPrefix"]

    connect() {
        // Initialize on connect
        this.updateLabel()
        this.updatePlaceholder()
        this.updateFieldVisibility()
    }

    updateLabel() {
        const platform = this.platformTarget.value
        const label = this.labelTarget

        if (platform === 'website' || platform === 'other') {
            label.textContent = 'URL'
        } else {
            label.textContent = 'Username/Handle'
        }

        this.updatePlaceholder()
        this.updateFieldVisibility()
    }

    updatePlaceholder() {
        const platform = this.platformTarget.value
        const handleInput = this.handleTarget

        if (platform === 'website' || platform === 'other') {
            handleInput.placeholder = 'example.com'
        } else {
            handleInput.placeholder = 'your-username'
        }
    }

    updateFieldVisibility() {
        const platform = this.platformTarget.value
        const isWebsiteOrOther = platform === 'website' || platform === 'other'

        // Show/hide name field
        if (this.hasNameFieldTarget) {
            if (isWebsiteOrOther) {
                this.nameFieldTarget.classList.remove('hidden')
            } else {
                this.nameFieldTarget.classList.add('hidden')
            }
        }

        // Show/hide URL prefix and adjust input padding
        if (this.hasUrlPrefixTarget) {
            if (isWebsiteOrOther) {
                this.urlPrefixTarget.classList.remove('hidden')
                // Add left padding to make room for https:// prefix
                this.handleTarget.classList.add('pl-[4.5rem]')
            } else {
                this.urlPrefixTarget.classList.add('hidden')
                // Remove left padding
                this.handleTarget.classList.remove('pl-[4.5rem]')
            }
        }
    }

    // Helper to get proper platform display name
    getPlatformDisplayName(platform) {
        const displayNames = {
            'youtube': 'YouTube',
            'tiktok': 'TikTok',
            'linkedin': 'LinkedIn',
            'instagram': 'Instagram',
            'facebook': 'Facebook',
            'twitter': 'Twitter',
            'website': 'Website',
            'other': 'Other'
        }
        return displayNames[platform] || platform.charAt(0).toUpperCase() + platform.slice(1)
    }
}
