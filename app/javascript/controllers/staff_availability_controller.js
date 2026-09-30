import { Controller } from "@hotwired/stimulus"

// Staffing → Availability: clicking a day on the calendar opens the day modal
// and loads that day (everyone, grouped by whether they can work) into its
// Turbo frame.
export default class extends Controller {
    static targets = ["modal", "frame", "title"]

    openDay(event) {
        if (event.type === "keydown") event.preventDefault()
        const cell = event.currentTarget.dataset
        if (this.hasTitleTarget) this.titleTarget.textContent = cell.title || "Availability"
        if (this.hasFrameTarget) this.frameTarget.src = cell.url
        this.modalTarget.classList.remove("hidden")
    }

    close(event) {
        if (event && event.type !== "keydown") event.preventDefault()
        this.modalTarget.classList.add("hidden")
    }

    backdropClose(event) {
        if (event.target === this.modalTarget || event.target.parentElement === this.modalTarget) this.close()
    }
}
