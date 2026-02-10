import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["panel", "orgPopup", "userPopup", "dashboardPopup", "profilePopup"]

    connect() {
        this.open = false
        this._handleKeydown = this._handleKeydown.bind(this)
        document.addEventListener("keydown", this._handleKeydown)
    }

    disconnect() {
        document.removeEventListener("keydown", this._handleKeydown)
    }

    toggle() {
        this.open = !this.open
        this.panelTarget.classList.toggle("hidden", !this.open)
    }

    showOrgPopup() {
        if (this.hasOrgPopupTarget) {
            this.orgPopupTarget.classList.remove("hidden")
        }
    }

    hideOrgPopup() {
        if (this.hasOrgPopupTarget) {
            this.orgPopupTarget.classList.add("hidden")
        }
    }

    showUserPopup() {
        if (this.hasUserPopupTarget) {
            this.userPopupTarget.classList.remove("hidden")
        }
    }

    hideUserPopup() {
        if (this.hasUserPopupTarget) {
            this.userPopupTarget.classList.add("hidden")
        }
    }

    showDashboardPopup() {
        if (this.hasDashboardPopupTarget) {
            this.dashboardPopupTarget.classList.remove("hidden")
        }
    }

    hideDashboardPopup() {
        if (this.hasDashboardPopupTarget) {
            this.dashboardPopupTarget.classList.add("hidden")
        }
    }

    showProfilePopup() {
        if (this.hasProfilePopupTarget) {
            this.profilePopupTarget.classList.remove("hidden")
        }
    }

    hideProfilePopup() {
        if (this.hasProfilePopupTarget) {
            this.profilePopupTarget.classList.add("hidden")
        }
    }

    _handleKeydown(event) {
        if (event.key === "Escape") {
            if (this.hasProfilePopupTarget && !this.profilePopupTarget.classList.contains("hidden")) {
                this.hideProfilePopup()
            } else if (this.hasDashboardPopupTarget && !this.dashboardPopupTarget.classList.contains("hidden")) {
                this.hideDashboardPopup()
            } else if (this.hasOrgPopupTarget && !this.orgPopupTarget.classList.contains("hidden")) {
                this.hideOrgPopup()
            } else if (this.hasUserPopupTarget && !this.userPopupTarget.classList.contains("hidden")) {
                this.hideUserPopup()
            } else if (this.open) {
                this.toggle()
            }
        }
    }
}
