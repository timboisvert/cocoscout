import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["content", "icon"]
    static values = {
        initialState: { type: String, default: "open" },
        storageKey: String
    }

    connect() {
        // Check localStorage if storageKey is provided
        if (this.hasStorageKeyValue) {
            const savedState = localStorage.getItem(this.storageKeyValue)
            if (savedState === "closed") {
                this.close()
            } else {
                this.open()
            }
        } else {
            // Use initial state value
            if (this.initialStateValue === "closed") {
                this.close()
            } else {
                this.open()
            }
        }
    }

    toggle() {
        if (this.contentTarget.classList.contains("hidden")) {
            this.open()
        } else {
            this.close()
        }
    }

    open() {
        this.contentTarget.classList.remove("hidden")
        if (this.hasIconTarget) {
            this.iconTarget.style.transform = "rotate(180deg)"
        }
        if (this.hasStorageKeyValue) {
            localStorage.setItem(this.storageKeyValue, "open")
        }
    }

    close() {
        this.contentTarget.classList.add("hidden")
        if (this.hasIconTarget) {
            this.iconTarget.style.transform = "rotate(0deg)"
        }
        if (this.hasStorageKeyValue) {
            localStorage.setItem(this.storageKeyValue, "closed")
        }
    }
}
