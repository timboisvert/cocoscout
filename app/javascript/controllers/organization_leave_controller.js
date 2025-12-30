import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "form", "orgName"]

    openConfirm(event) {
        const orgId = event.currentTarget.dataset.orgId
        const orgName = event.currentTarget.dataset.orgName

        this.orgNameTarget.textContent = orgName
        this.formTarget.action = `/account/organizations/${orgId}/leave`
        this.modalTarget.classList.remove("hidden")
    }

    closeConfirm() {
        this.modalTarget.classList.add("hidden")
    }
}
