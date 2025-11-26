import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["sentinel", "nextLink"]
    static values = {
        url: String,
        page: Number,
        pages: Number
    }

    connect() {
        console.log(`Infinite scroll connected: page ${this.pageValue} of ${this.pagesValue}`)

        if (this.pageValue < this.pagesValue && this.hasSentinelTarget) {
            console.log("Setting up IntersectionObserver")
            this.observer = new IntersectionObserver(
                entries => this.handleIntersect(entries),
                {
                    root: null,
                    rootMargin: "200px",
                    threshold: 0.1
                }
            )
            this.observer.observe(this.sentinelTarget)
            console.log("Observer is watching sentinel")
        } else {
            console.log("No more pages or sentinel missing")
        }
    }

    disconnect() {
        if (this.observer) {
            this.observer.disconnect()
        }
    }

    handleIntersect(entries) {
        entries.forEach(entry => {
            console.log("Intersection event:", entry.isIntersecting, "Has link:", this.hasNextLinkTarget)
            if (entry.isIntersecting && this.hasNextLinkTarget) {
                console.log("Triggering load more")
                this.nextLinkTarget.click()
                this.observer.disconnect()
            }
        })
    }
}
