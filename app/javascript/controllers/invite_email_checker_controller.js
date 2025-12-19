import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["emailInput", "profilesSection", "profilesList", "form"]

  checkEmail() {
    const email = this.emailInputTarget.value.trim().toLowerCase()
    
    if (!email || !email.includes("@")) {
      this.hideProfilesSection()
      return
    }

    fetch(`/manage/people/check_email?email=${encodeURIComponent(email)}`, {
      headers: {
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      }
    })
      .then(response => response.json())
      .then(data => {
        if (data.profiles && data.profiles.length > 1) {
          this.showProfilesSection(data.profiles)
        } else {
          this.hideProfilesSection()
        }
      })
      .catch(error => {
        console.error("Error checking email:", error)
        this.hideProfilesSection()
      })
  }

  showProfilesSection(profiles) {
    // Build the profiles list HTML
    let html = ""
    profiles.forEach(profile => {
      const disabled = profile.already_in_org ? "disabled" : ""
      const opacity = profile.already_in_org ? "opacity-50" : ""
      const alreadyInOrg = profile.already_in_org 
        ? '<span class="text-xs text-gray-500 ml-2">(Already in organization)</span>' 
        : ""
      
      html += `
        <label class="flex items-center gap-3 p-2 rounded-lg hover:bg-yellow-100 cursor-pointer ${opacity}">
          <input type="checkbox" 
                 name="selected_profile_ids[]" 
                 value="${profile.id}"
                 ${disabled}
                 class="rounded border-gray-300 text-pink-500 focus:ring-pink-500">
          <div>
            <span class="text-sm font-medium text-gray-900">${profile.name}</span>
            ${alreadyInOrg}
          </div>
        </label>
      `
    })

    this.profilesListTarget.innerHTML = html
    this.profilesSectionTarget.classList.remove("hidden")
  }

  hideProfilesSection() {
    this.profilesSectionTarget.classList.add("hidden")
    this.profilesListTarget.innerHTML = ""
  }
}
