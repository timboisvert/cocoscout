import { Controller } from "@hotwired/stimulus"

// Controls a welcome/onboarding modal shown after creating a sign-up form
export default class extends Controller {
    static targets = ["modal"]
    static values = {
        autoShow: { type: Boolean, default: false }
    }

    connect() {
        if (this.autoShowValue) {
            this.open()
            // Remove just_created from URL so modal doesn't re-show on auto-refresh
            this.removeJustCreatedParam()
        }
    }

    removeJustCreatedParam() {
        const url = new URL(window.location)
        if (url.searchParams.has("just_created")) {
            url.searchParams.delete("just_created")
            window.history.replaceState({}, "", url)
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
}
