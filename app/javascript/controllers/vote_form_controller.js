import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["comment"]
    static values = { saveUrl: String }

    // Get the visible comment input (handles mobile/desktop dual inputs)
    getVisibleCommentValue() {
        for (const target of this.commentTargets) {
            // Check if the element or its parent container is visible
            if (target.offsetParent !== null) {
                return target.value
            }
        }
        // Fallback to first target if none visible (shouldn't happen)
        return this.commentTarget.value
    }

    submitVote(event) {
        const vote = event.params.vote
        const url = event.params.url
        const comment = this.getVisibleCommentValue()

        // Save current tab
        const currentTab = this.getCurrentTab()

        // Create a form and submit it
        const form = document.createElement('form')
        form.method = 'POST'
        form.action = url

        // Add CSRF token
        const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
        if (csrfToken) {
            const csrfInput = document.createElement('input')
            csrfInput.type = 'hidden'
            csrfInput.name = 'authenticity_token'
            csrfInput.value = csrfToken
            form.appendChild(csrfInput)
        }

        // Add vote
        const voteInput = document.createElement('input')
        voteInput.type = 'hidden'
        voteInput.name = 'vote'
        voteInput.value = vote
        form.appendChild(voteInput)

        // Add comment
        const commentInput = document.createElement('input')
        commentInput.type = 'hidden'
        commentInput.name = 'comment'
        commentInput.value = comment
        form.appendChild(commentInput)

        // Add current tab to preserve it after redirect
        if (currentTab !== null) {
            const tabInput = document.createElement('input')
            tabInput.type = 'hidden'
            tabInput.name = 'tab'
            tabInput.value = currentTab
            form.appendChild(tabInput)
        }

        document.body.appendChild(form)
        form.submit()
    }

    getCurrentTab() {
        // Get current tab - check hash first
        const hash = window.location.hash
        if (hash && hash.startsWith('#tab-')) {
            return hash.replace('#tab-', '')
        }

        // Fallback to query param
        const currentParams = new URLSearchParams(window.location.search)
        if (currentParams.has('tab')) {
            return currentParams.get('tab')
        }

        return null
    }

    submitComment(event) {
        const url = event.params.url
        const comment = this.getVisibleCommentValue()

        // Save current tab
        const currentTab = this.getCurrentTab()

        // Create a form and submit it (saves comment only, no vote change)
        const form = document.createElement('form')
        form.method = 'POST'
        form.action = url

        // Add CSRF token
        const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
        if (csrfToken) {
            const csrfInput = document.createElement('input')
            csrfInput.type = 'hidden'
            csrfInput.name = 'authenticity_token'
            csrfInput.value = csrfToken
            form.appendChild(csrfInput)
        }

        // Add comment only (no vote param means keep existing vote)
        const commentInput = document.createElement('input')
        commentInput.type = 'hidden'
        commentInput.name = 'comment'
        commentInput.value = comment
        form.appendChild(commentInput)

        // Add current tab to preserve it after redirect
        if (currentTab !== null) {
            const tabInput = document.createElement('input')
            tabInput.type = 'hidden'
            tabInput.name = 'tab'
            tabInput.value = currentTab
            form.appendChild(tabInput)
        }

        document.body.appendChild(form)
        form.submit()
    }

    // Navigate to another page, saving comment first via fetch
    async navigateWithSave(event) {
        event.preventDefault()
        const targetUrl = event.currentTarget.href
        const comment = this.getVisibleCommentValue()
        const saveUrl = this.saveUrlValue

        // Only save if there's a comment and a save URL
        if (comment && saveUrl) {
            const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
            try {
                await fetch(saveUrl, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/x-www-form-urlencoded',
                        'X-CSRF-Token': csrfToken,
                        'Accept': 'text/html'
                    },
                    body: `comment=${encodeURIComponent(comment)}`
                })
            } catch (e) {
                // Continue with navigation even if save fails
                console.error('Failed to save comment:', e)
            }
        }

        // Navigate to the target URL with current tab preserved
        const url = new URL(targetUrl, window.location.origin)

        // Get current tab - check hash first, then query param
        let tabIndex = null
        const hash = window.location.hash
        if (hash && hash.startsWith('#tab-')) {
            tabIndex = hash.replace('#tab-', '')
        } else {
            // Fallback to query param (if page was loaded with ?tab=X)
            const currentParams = new URLSearchParams(window.location.search)
            if (currentParams.has('tab')) {
                tabIndex = currentParams.get('tab')
            }
        }

        if (tabIndex !== null) {
            url.searchParams.set('tab', tabIndex)
        }

        window.location.href = url.toString()
    }
}
