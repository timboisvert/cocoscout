import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["sentinel", "nextLink"]
    static values = {
        url: String,
        page: Number,
        pages: Number
    }

    connect() {
        if (this.pageValue < this.pagesValue && this.hasSentinelTarget) {
            this.observer = new IntersectionObserver(
                entries => this.handleIntersect(entries),
                {
                    root: null,
                    rootMargin: "200px",
                    threshold: 0.1
                }
            )
            this.observer.observe(this.sentinelTarget)
        }
    }

    disconnect() {
        if (this.observer) {
            this.observer.disconnect()
        }
    }

    handleIntersect(entries) {
        entries.forEach(entry => {
            if (entry.isIntersecting && this.hasNextLinkTarget) {
                this.nextLinkTarget.click()
                this.observer.disconnect()
            }
        })
    }
}
