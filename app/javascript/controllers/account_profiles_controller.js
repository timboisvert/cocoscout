import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["archiveModal", "archiveName", "archiveForm"]

    openArchive(event) {
        const profileId = event.currentTarget.dataset.profileId
        const profileName = event.currentTarget.dataset.profileName

        this.archiveNameTarget.textContent = profileName
        this.archiveFormTarget.action = `/account/profiles/${profileId}/archive`
        this.archiveModalTarget.classList.remove("hidden")
    }

    closeArchive() {
        this.archiveModalTarget.classList.add("hidden")
    }
}
