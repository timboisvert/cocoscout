import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["durationSelect", "customDateField", "extendForm", "previewContainer", "previewList", "previewCount", "previewThrough", "previewError", "previewButton", "confirmForm"]
    static values = { previewUrl: String, extendUrl: String }

    close() {
        const frame = document.getElementById('recurring_series_modal')
        if (frame) {
            frame.innerHTML = ''
        }
    }

    closeOnBackdrop(event) {
        if (event.target === this.element) {
            this.close()
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    toggleCustomDate() {
        if (!this.hasDurationSelectTarget || !this.hasCustomDateFieldTarget) return

        const isCustom = this.durationSelectTarget.value === 'custom'
        this.customDateFieldTarget.classList.toggle('hidden', !isCustom)

        // Reset preview when changing duration
        this.hidePreview()
    }

    async previewExtend(event) {
        event.preventDefault()

        const form = this.extendFormTarget
        const formData = new FormData(form)
        const button = this.previewButtonTarget
        const originalText = button.querySelector('span')?.textContent || button.textContent

        // Show loading state
        if (button.querySelector('span')) {
            button.querySelector('span').textContent = 'Loading...'
        } else {
            button.textContent = 'Loading...'
        }
        button.disabled = true

        try {
            const response = await fetch(this.previewUrlValue, {
                method: 'POST',
                body: formData,
                headers: {
                    'Accept': 'application/json',
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
                }
            })

            const data = await response.json()

            if (!response.ok) {
                this.showPreviewError(data.error || 'Something went wrong')
                return
            }

            this.showPreview(data, formData)
        } catch (error) {
            this.showPreviewError('Failed to preview dates. Please try again.')
        } finally {
            if (button.querySelector('span')) {
                button.querySelector('span').textContent = originalText
            } else {
                button.textContent = originalText
            }
            button.disabled = false
        }
    }

    showPreview(data, formData) {
        // Hide the extend form options
        this.extendFormTarget.classList.add('hidden')

        // Build the date list
        const listHtml = data.dates.map(d =>
            `<li class="flex items-center justify-between py-2 px-3 text-sm">
                <span class="font-medium text-gray-900">${d.display}</span>
                <span class="text-gray-500">${d.time}</span>
            </li>`
        ).join('')

        this.previewListTarget.innerHTML = listHtml
        this.previewCountTarget.textContent = `${data.count} new event${data.count === 1 ? '' : 's'}`
        this.previewThroughTarget.textContent = data.extend_through

        // Copy form params to confirm form
        const confirmForm = this.confirmFormTarget
        // Clear existing hidden inputs (except CSRF)
        confirmForm.querySelectorAll('input[type="hidden"]:not([name="authenticity_token"])').forEach(el => el.remove())
        for (const [key, value] of formData.entries()) {
            if (key === 'authenticity_token') continue
            const input = document.createElement('input')
            input.type = 'hidden'
            input.name = key
            input.value = value
            confirmForm.appendChild(input)
        }

        // Show preview
        this.previewContainerTarget.classList.remove('hidden')
        this.previewErrorTarget.classList.add('hidden')
    }

    showPreviewError(message) {
        this.previewErrorTarget.textContent = message
        this.previewErrorTarget.classList.remove('hidden')
        this.previewContainerTarget.classList.add('hidden')
    }

    hidePreview() {
        if (this.hasPreviewContainerTarget) {
            this.previewContainerTarget.classList.add('hidden')
        }
        if (this.hasPreviewErrorTarget) {
            this.previewErrorTarget.classList.add('hidden')
        }
        if (this.hasExtendFormTarget) {
            this.extendFormTarget.classList.remove('hidden')
        }
    }

    backToOptions() {
        this.hidePreview()
    }
}
