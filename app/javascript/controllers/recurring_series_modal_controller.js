import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "tab", "panel",
        "extendForm", "previewContainer", "previewList",
        "previewCount", "previewThrough", "previewError", "previewButton", "confirmForm",
        "rescheduleForm", "reschedulePreviewButton", "rescheduleError", "reschedulePreviewContainer",
        "rescheduleList", "rescheduleRemoving", "rescheduleKeeping", "rescheduleAdding", "rescheduleFromLabel",
        "rescheduleUntil", "reschedulePattern", "rescheduleTime", "rescheduleConfirmForm",
        "rescheduleFrom", "patternSelect"
    ]
    static values = { previewUrl: String, previewRescheduleUrl: String }

    connect() {
        this.relabelPatterns()
    }

    // ==========================================
    // Tabs: Events / Extend / Change schedule
    // ==========================================

    showTab(event) {
        const name = event.params.tab
        const active = ["border-pink-500", "text-pink-600"]
        const idle = ["border-transparent", "text-gray-500", "hover:text-gray-700", "hover:border-gray-300"]
        this.tabTargets.forEach(tab => {
            const on = tab.dataset.recurringSeriesModalTabParam === name
            active.forEach(c => tab.classList.toggle(c, on))
            idle.forEach(c => tab.classList.toggle(c, !on))
            tab.setAttribute("aria-selected", on ? "true" : "false")
        })
        this.panelTargets.forEach(panel => {
            panel.classList.toggle("hidden", panel.dataset.panel !== name)
        })
    }

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

    // A new "until" date invalidates whatever preview was showing.
    extendDateChanged() {
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

    // ==========================================
    // Reschedule Future Events
    // ==========================================

    async previewReschedule(event) {
        event.preventDefault()

        const form = this.rescheduleFormTarget
        const formData = new FormData(form)

        const button = this.reschedulePreviewButtonTarget
        const originalSpan = button.querySelector('span')
        const originalText = originalSpan?.textContent || button.textContent

        if (originalSpan) { originalSpan.textContent = 'Loading...' } else { button.textContent = 'Loading...' }
        button.disabled = true

        try {
            const response = await fetch(this.previewRescheduleUrlValue, {
                method: 'POST',
                body: formData,
                headers: {
                    'Accept': 'application/json',
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
                }
            })

            const data = await response.json()

            if (!response.ok) {
                this.showRescheduleError(data.error || 'Something went wrong')
                return
            }

            this.showReschedulePreview(data, formData)
        } catch (error) {
            this.showRescheduleError('Failed to preview reschedule. Please try again.')
        } finally {
            if (originalSpan) { originalSpan.textContent = originalText } else { button.textContent = originalText }
            button.disabled = false
        }
    }

    showReschedulePreview(data, formData) {
        this.rescheduleFormTarget.classList.add('hidden')

        const listHtml = data.dates.map(d =>
            `<li class="flex items-center justify-between py-2 px-3 text-sm">
                <span class="font-medium text-gray-900">${d.display}</span>
                <span class="text-gray-500">${d.time}</span>
            </li>`
        ).join('')

        this.rescheduleListTarget.innerHTML = listHtml
        this.rescheduleRemovingTarget.textContent = `${data.removing} event${data.removing === 1 ? '' : 's'}`
        this.rescheduleKeepingTarget.textContent = data.keeping > 0
            ? `(${data.keeping} earlier event${data.keeping === 1 ? ' stays' : 's stay'} as ${data.keeping === 1 ? 'it is' : 'they are'})`
            : ''
        this.rescheduleAddingTarget.textContent = `${data.adding} new event${data.adding === 1 ? '' : 's'}`
        this.rescheduleFromLabelTarget.textContent = data.from
        this.rescheduleUntilTarget.textContent = data.until
        this.reschedulePatternTarget.textContent = data.pattern.toLowerCase()
        this.rescheduleTimeTarget.textContent = data.time

        // Copy form params to confirm form
        const confirmForm = this.rescheduleConfirmFormTarget
        confirmForm.querySelectorAll('input[type="hidden"]:not([name="authenticity_token"])').forEach(el => el.remove())
        for (const [key, value] of formData.entries()) {
            if (key === 'authenticity_token') continue
            const input = document.createElement('input')
            input.type = 'hidden'
            input.name = key
            input.value = value
            confirmForm.appendChild(input)
        }

        this.reschedulePreviewContainerTarget.classList.remove('hidden')
        this.rescheduleErrorTarget.classList.add('hidden')
    }

    showRescheduleError(message) {
        this.rescheduleErrorTarget.textContent = message
        this.rescheduleErrorTarget.classList.remove('hidden')
        this.reschedulePreviewContainerTarget.classList.add('hidden')
    }

    backToRescheduleOptions() {
        this.reschedulePreviewContainerTarget.classList.add('hidden')
        this.rescheduleErrorTarget.classList.add('hidden')
        this.rescheduleFormTarget.classList.remove('hidden')
    }

    // Say what each pattern means for THIS first event — "Weekly on Saturdays",
    // "Monthly on the 17th", "Monthly on the third Saturday" — instead of the
    // generic "same date / same weekday". Values and the selection are kept.
    relabelPatterns() {
        if (!this.hasPatternSelectTarget || !this.hasRescheduleFromTarget) return
        const value = this.rescheduleFromTarget.value
        if (!value) return
        const date = new Date(value)
        if (isNaN(date)) return

        const day = date.toLocaleDateString('en-US', { weekday: 'long' })
        const dom = date.getDate()
        const ordinalWords = ["first", "second", "third", "fourth", "fifth"]
        const weekOrdinal = ordinalWords[Math.ceil(dom / 7) - 1] || `${Math.ceil(dom / 7)}th`
        const suffix = (n) => { const s = ["th", "st", "nd", "rd"], v = n % 100; return n + (s[(v - 20) % 10] || s[v] || s[0]) }

        const labels = {
            daily: "Daily",
            weekly: `Weekly on ${day}s`,
            biweekly: `Every other ${day}`,
            monthly_date: `Monthly on the ${suffix(dom)}`,
            monthly_week: `Monthly on the ${weekOrdinal} ${day}`
        }
        Array.from(this.patternSelectTarget.options).forEach(option => {
            if (labels[option.value]) option.textContent = labels[option.value]
        })
    }

    // Any change to the inputs invalidates a preview that's showing.
    rescheduleChanged() {
        if (this.hasReschedulePreviewContainerTarget && !this.reschedulePreviewContainerTarget.classList.contains('hidden')) {
            this.backToRescheduleOptions()
        }
    }
}
