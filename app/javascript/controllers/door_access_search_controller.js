import { Controller } from "@hotwired/stimulus"

// "Add someone else" on Ticketing settings → Door access and on a show's or
// production's Visibility page. The shared People Picker (shared/_people_picker,
// the id in pickerValue) finds them, or takes an email to invite; this shows
// who was picked with the level or scope choice, and the form posts to the
// grant url for a person or the invite url for an email.
export default class extends Controller {
    static targets = ["searchSection", "form", "personId", "email", "name", "selectedName", "selectedEmail", "submit"]
    static values = { picker: String, grantUrl: String, inviteUrl: String, grantText: String, inviteText: String }

    // people-picker:pick from the sheet.
    picked(event) {
        const pick = event.detail
        if (pick.picker !== this.pickerValue) return
        if (pick.invite) {
            this.show({ personId: "", email: pick.email, name: pick.name || "", label: pick.name || pick.email,
                        detail: pick.name ? pick.email : "They'll make a free account when they accept",
                        url: this.inviteUrlValue, text: this.inviteTextValue })
        } else if (pick.type === "Person") {
            this.show({ personId: pick.id, email: "", name: "", label: pick.name, detail: pick.email || "",
                        url: this.grantUrlValue, text: this.grantTextValue })
        }
    }

    show({ personId, email, name, label, detail, url, text }) {
        this.personIdTarget.value = personId
        this.emailTarget.value = email
        this.nameTarget.value = name
        this.selectedNameTarget.textContent = label
        this.selectedEmailTarget.textContent = detail
        this.formTarget.action = url
        if (this.hasSubmitTarget && text) this.submitTarget.textContent = text
        this.searchSectionTarget.classList.add("hidden")
        this.formTarget.classList.remove("hidden")
    }

    back() {
        this.personIdTarget.value = ""
        this.emailTarget.value = ""
        this.nameTarget.value = ""
        this.formTarget.classList.add("hidden")
        this.searchSectionTarget.classList.remove("hidden")
    }
}
