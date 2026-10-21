import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "searchSection",
        "selectedUser", "selectedUserName", "selectedUserEmail",
        "userIdInput", "emailInput",
        "roleSection", "inviteSection"
    ]
    static values = { url: String, formUrl: String }

    // people-picker:pick from the shared People Picker ("team-picker"): a
    // person with an account, or an email to invite.
    picked(event) {
        const pick = event.detail
        if (pick.picker !== "team-picker") return
        if (pick.invite) return this.showInvite(pick.email)
        if (!pick.userId) return
        this.select(pick.userId, pick.name, pick.email || "")
    }

    selectUser(event) {
        this.select(event.currentTarget.dataset.userId, event.currentTarget.dataset.userName, event.currentTarget.dataset.userEmail)
    }

    select(userId, userName, userEmail) {

        // Hide search, show selected user + role selection
        this.searchSectionTarget.classList.add("hidden")
        this.selectedUserTarget.classList.remove("hidden")
        this.roleSectionTarget.classList.remove("hidden")

        // Set display info
        this.selectedUserNameTarget.textContent = userName
        this.selectedUserEmailTarget.textContent = userEmail

        // Set hidden form field
        this.userIdInputTarget.value = userId
        this.emailInputTarget.value = ""
    }

    showInviteForm(event) {
        this.showInvite(event.currentTarget.dataset.email || "")
    }

    showInvite(email) {

        // Hide search, show invite form + role selection
        this.searchSectionTarget.classList.add("hidden")
        this.inviteSectionTarget.classList.remove("hidden")
        this.roleSectionTarget.classList.remove("hidden")

        // Set the email
        this.emailInputTarget.value = email
        this.userIdInputTarget.value = ""
    }

    backToSearch() {
        // Show search, hide everything else
        this.searchSectionTarget.classList.remove("hidden")
        this.selectedUserTarget.classList.add("hidden")
        this.roleSectionTarget.classList.add("hidden")
        this.inviteSectionTarget.classList.add("hidden")

        // Clear hidden fields
        this.userIdInputTarget.value = ""
        this.emailInputTarget.value = ""

    }

    reset() {
        this.userIdInputTarget.value = ""
        this.emailInputTarget.value = ""
        this.searchSectionTarget.classList.remove("hidden")
        this.selectedUserTarget.classList.add("hidden")
        this.roleSectionTarget.classList.add("hidden")
        this.inviteSectionTarget.classList.add("hidden")
    }
}
