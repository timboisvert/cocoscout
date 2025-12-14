import { Controller } from "@hotwired/stimulus"

// Controller for managing linked vacancy decision UI
// Shows/hides the invitation section and close section based on producer's choice
export default class extends Controller {
    static targets = ["recastRadio", "noActionRadio", "inviteSection", "closeSection"]

    connect() {
        // Check if there are already invitations sent - if so, show invite section and select recast
        if (this.hasInviteSectionTarget && this.inviteSectionTarget.querySelector('.bg-white')) {
            // There's content, check if we should auto-select recast based on existing invitations
            this.updateVisibility()
        }
    }

    selectRecast() {
        if (this.hasRecastRadioTarget) {
            this.recastRadioTarget.checked = true
        }
        this.showInviteSection()
        this.hideCloseSection()
    }

    selectNoAction() {
        if (this.hasNoActionRadioTarget) {
            this.noActionRadioTarget.checked = true
        }
        this.hideInviteSection()
        this.showCloseSection()
    }

    showInviteSection() {
        if (this.hasInviteSectionTarget) {
            this.inviteSectionTarget.classList.remove('hidden')
        }
    }

    hideInviteSection() {
        if (this.hasInviteSectionTarget) {
            this.inviteSectionTarget.classList.add('hidden')
        }
    }

    showCloseSection() {
        if (this.hasCloseSectionTarget) {
            this.closeSectionTarget.classList.remove('hidden')
        }
    }

    hideCloseSection() {
        if (this.hasCloseSectionTarget) {
            this.closeSectionTarget.classList.add('hidden')
        }
    }

    updateVisibility() {
        if (this.hasRecastRadioTarget && this.recastRadioTarget.checked) {
            this.showInviteSection()
            this.hideCloseSection()
        } else if (this.hasNoActionRadioTarget && this.noActionRadioTarget.checked) {
            this.hideInviteSection()
            this.showCloseSection()
        }
    }
}
