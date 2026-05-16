import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["comment", "count"]
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
        const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

        console.log('[vote-form] submitVote ->', url, { vote, comment })

        fetch(url, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': csrfToken,
                'Accept': 'application/json'
            },
            body: JSON.stringify({ vote, comment })
        })
            .then(r => {
                console.log('[vote-form] vote response status', r.status, 'content-type', r.headers.get('content-type'))
                return r.json()
            })
            .then(data => {
                console.log('[vote-form] vote response data', data)
                if (data.success) {
                    this.updateVoteButtons(vote)
                    this.updateCounts(data.counts)
                    this.updateVotesList(data.votes_html)
                }
            })
            .catch(e => console.error('[vote-form] Vote failed:', e))
    }

    updateCounts(counts) {
        if (!counts) return
        this.countTargets.forEach(span => {
            const key = span.dataset.voteCount
            if (counts[key] !== undefined && counts[key] !== null) {
                span.textContent = counts[key]
            }
        })
    }

    updateVotesList(html) {
        if (typeof html !== 'string') return
        const list = document.getElementById('votes-list')
        const container = document.getElementById('votes-list-container')
        if (list) list.innerHTML = html
        if (container) {
            // Show the container if it has any content (non-whitespace)
            if (html.trim().length > 0) {
                container.classList.remove('hidden')
            } else {
                container.classList.add('hidden')
            }
        }
    }

    updateVoteButtons(selectedVote) {
        // Update all vote buttons in this controller's scope
        const activeClasses = ['bg-pink-500', 'hover:bg-pink-600', 'text-white']
        const inactiveClasses = ['bg-white', 'border', 'border-gray-300', 'hover:bg-gray-50', 'text-gray-700']

        this.element.querySelectorAll('[data-vote-form-vote-param]').forEach(btn => {
            const btnVote = btn.dataset.voteFormVoteParam
            if (btnVote === selectedVote) {
                btn.classList.remove(...inactiveClasses)
                btn.classList.add(...activeClasses)
            } else {
                btn.classList.remove(...activeClasses)
                btn.classList.add(...inactiveClasses)
            }
        })
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
        const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
        const btn = event.currentTarget

        console.log('[vote-form] submitComment ->', url, { comment })

        fetch(url, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': csrfToken,
                'Accept': 'application/json'
            },
            body: JSON.stringify({ comment })
        })
            .then(r => {
                console.log('[vote-form] response status', r.status, 'content-type', r.headers.get('content-type'))
                return r.json()
            })
            .then(data => {
                console.log('[vote-form] response data', data)
                console.log('[vote-form] votes_html length', data?.votes_html?.length)
                console.log('[vote-form] votes-list element', document.getElementById('votes-list'))
                if (data.success) {
                    const originalText = btn.textContent
                    btn.textContent = '✓'
                    setTimeout(() => { btn.textContent = originalText }, 1500)
                    this.updateCounts(data.counts)
                    this.updateVotesList(data.votes_html)
                }
            })
            .catch(e => console.error('[vote-form] Comment save failed:', e))
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
