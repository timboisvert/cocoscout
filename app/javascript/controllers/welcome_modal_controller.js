import { Controller } from "@hotwired/stimulus"

// Controls a welcome/onboarding modal that can be dismissed permanently
export default class extends Controller {
    static targets = ["modal"]
    static values = {
        storageKey: String,
        autoShow: { type: Boolean, default: false }
    }

    connect() {
        if (this.autoShowValue && !this.isDismissedForever()) {
            this.open()
        }
    }

    open() {
        if (this.hasModalTarget) {
            this.modalTarget.classList.remove("hidden")
            document.body.style.overflow = "hidden"
        }
    }

    close() {
        if (this.hasModalTarget) {
            this.modalTarget.classList.add("hidden")
            document.body.style.overflow = ""
        }
    }

    dismissForever() {
        if (this.hasStorageKeyValue) {
            localStorage.setItem(this.storageKeyValue, "dismissed")
        }
        this.close()
    }

    isDismissedForever() {
        if (!this.hasStorageKeyValue) return false
        return localStorage.getItem(this.storageKeyValue) === "dismissed"
    }
}
