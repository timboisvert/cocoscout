import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="scroll-indicator"
export default class extends Controller {
    static targets = ["indicator"]

    connect() {
        this.checkScroll()
        this.boundCheckScroll = this.checkScroll.bind(this)
        window.addEventListener("scroll", this.boundCheckScroll)
    }

    disconnect() {
        window.removeEventListener("scroll", this.boundCheckScroll)
    }

    checkScroll() {
        // Hide the indicator if user has scrolled more than 100px
        if (window.scrollY > 100) {
            this.indicatorTarget.classList.add("opacity-0", "pointer-events-none")
        } else {
            this.indicatorTarget.classList.remove("opacity-0", "pointer-events-none")
        }
    }

    scrollDown() {
        // Scroll down smoothly by viewport height minus some offset
        window.scrollBy({
            top: window.innerHeight * 0.6,
            behavior: "smooth"
        })
    }
}
