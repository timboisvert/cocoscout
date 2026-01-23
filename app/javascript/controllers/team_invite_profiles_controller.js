import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["email", "profilesSection", "profilesList"]
    static values = { checkUrl: String }

    async checkProfiles() {
        const email = this.emailTarget.value.trim().toLowerCase()
        if (!email || !email.includes("@")) {
            this.hideProfiles()
            return
        }

        try {
            const response = await fetch(this.checkUrlValue, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
                },
                body: JSON.stringify({ email: email })
            })

            const data = await response.json()

            if (data.profiles && data.profiles.length > 1) {
                this.showProfiles(data.profiles)
            } else {
                this.hideProfiles()
            }
        } catch (error) {
            console.error("Error checking profiles:", error)
            this.hideProfiles()
        }
    }

    showProfiles(profiles) {
        let html = ""
        profiles.forEach((profile, index) => {
            const disabled = profile.already_in_org ? "disabled" : ""
            const opacity = profile.already_in_org ? "opacity-50" : ""
            const alreadyInOrg = profile.already_in_org
                ? '<span class="text-xs text-gray-500 ml-2">(Already in organization)</span>'
                : ""
            const orgsText = profile.organizations.length > 0
                ? `<div class="text-xs text-gray-500">Member of: ${profile.organizations.join(", ")}</div>`
                : ""

            html += `
                <label class="flex items-center gap-3 p-3 rounded-lg border border-gray-200 hover:border-pink-300 hover:bg-pink-50 cursor-pointer transition has-[:checked]:border-pink-500 has-[:checked]:bg-pink-50 ${opacity}">
                    <input type="radio"
                           name="team_invitation[person_id]"
                           value="${profile.id}"
                           ${index === 0 && !profile.already_in_org ? "checked" : ""}
                           ${disabled}
                           class="text-pink-500 focus:ring-pink-500">
                    <div class="flex-1">
                        <div class="font-medium text-gray-900">${profile.name}${alreadyInOrg}</div>
                        ${orgsText}
                    </div>
                </label>
            `
        })

        this.profilesListTarget.innerHTML = html
        this.profilesSectionTarget.classList.remove("hidden")
    }

    hideProfiles() {
        this.profilesSectionTarget.classList.add("hidden")
        this.profilesListTarget.innerHTML = ""
    }
}
