import { Controller } from "@hotwired/stimulus"

// Handles instructor search with multi-select support.
// Supports adding multiple instructors with 3-tier results (org, global, invite).
export default class extends Controller {
    static targets = [
        "searchInput",
        "searchResults",
        "searchSection",
        "selectedList",
        "personIdsContainer",
        "inviteName",
        "inviteEmail",
        "inviteForm",
        "teamToggleSection",
        "instructorOptionsSection"
    ]

    static values = {
        searchUrl: String,
        inviteUrl: String
    }

    connect() {
        this.timeout = null
        this.selectedInstructors = []
        this._formAttr = ""

        // Load existing instructors from hidden inputs
        if (this.hasPersonIdsContainerTarget) {
            const inputs = this.personIdsContainerTarget.querySelectorAll('input[name="instructor_person_ids[]"]')
            inputs.forEach(input => {
                // Capture form attribute from server-rendered inputs
                if (!this._formAttr && input.getAttribute("form")) {
                    this._formAttr = input.getAttribute("form")
                }
                this.selectedInstructors.push({
                    id: input.value,
                    name: input.dataset.name || "",
                    email: input.dataset.email || "",
                    headshotUrl: input.dataset.headshotUrl || "",
                    bio: input.dataset.bio || "",
                    hasExistingHeadshot: input.dataset.hasExistingHeadshot === "true"
                })
            })
        }
    }

    search() {
        clearTimeout(this.timeout)
        this.timeout = setTimeout(() => this.performSearch(), 250)
    }

    async performSearch() {
        const query = this.searchInputTarget.value.trim()

        if (query.length < 2) {
            this.searchResultsTarget.innerHTML = '<p class="text-gray-500 text-sm p-4">Type at least 2 characters to search...</p>'
            return
        }

        this.searchResultsTarget.innerHTML = '<div class="flex justify-center p-4"><div class="animate-spin rounded-full h-6 w-6 border-b-2 border-pink-500"></div></div>'

        try {
            const response = await fetch(`${this.searchUrlValue}?q=${encodeURIComponent(query)}`, {
                headers: { "Accept": "text/html", "X-Requested-With": "XMLHttpRequest" }
            })

            if (response.ok) {
                this.searchResultsTarget.innerHTML = await response.text()
                this._disableAlreadySelected()
            } else {
                this.searchResultsTarget.innerHTML = '<p class="text-red-500 text-sm p-4">Error searching. Please try again.</p>'
            }
        } catch (error) {
            console.error("Instructor search error:", error)
            this.searchResultsTarget.innerHTML = '<p class="text-red-500 text-sm p-4">Error searching. Please try again.</p>'
        }
    }

    selectPerson(event) {
        event.preventDefault()
        const button = event.currentTarget
        const personId = button.dataset.personId
        const personName = button.dataset.personName
        const personEmail = button.dataset.personEmail || ""
        const personHeadshotUrl = button.dataset.personHeadshotUrl || ""

        // Prevent duplicates
        if (this.selectedInstructors.some(i => String(i.id) === String(personId))) return

        this._captureBios()
        this.selectedInstructors.push({
            id: personId,
            name: personName,
            email: personEmail,
            headshotUrl: personHeadshotUrl,
            bio: "",
            hasExistingHeadshot: false
        })

        this._renderSelectedList()
        this._updateHiddenInputs()
        this._showOptionsIfNeeded()
        this._disableAlreadySelected()

        // Clear search
        this.searchInputTarget.value = ""
        this.searchResultsTarget.innerHTML = ""
        this.searchInputTarget.focus()
    }

    removeInstructor(event) {
        event.preventDefault()
        const personId = event.currentTarget.dataset.personId
        this._captureBios()
        this.selectedInstructors = this.selectedInstructors.filter(i => String(i.id) !== String(personId))
        this._renderSelectedList()
        this._updateHiddenInputs()
        this._showOptionsIfNeeded()
        this._disableAlreadySelected()
    }

    showInviteForm(event) {
        event.preventDefault()
        const email = event.currentTarget.dataset.email || ""
        if (this.hasInviteFormTarget) {
            this.inviteEmailTarget.value = email
            this.inviteFormTarget.scrollIntoView({ behavior: "smooth" })
        }
    }

    async invitePerson(event) {
        event.preventDefault()
        const name = this.inviteNameTarget.value.trim()
        const email = this.inviteEmailTarget.value.trim()

        if (!name || !email) {
            alert("Please enter both name and email.")
            return
        }

        const button = event.currentTarget
        button.disabled = true
        const originalText = button.textContent
        button.textContent = "Sending..."

        try {
            const response = await fetch(this.inviteUrlValue, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                    "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
                },
                body: JSON.stringify({ name, email })
            })

            const data = await response.json()

            if (data.success) {
                this._captureBios()
                this.selectedInstructors.push({
                    id: data.person_id,
                    name: name,
                    email: email,
                    headshotUrl: "",
                    bio: "",
                    hasExistingHeadshot: false
                })
                this._renderSelectedList()
                this._updateHiddenInputs()
                this._showOptionsIfNeeded()

                // Reset invite form
                this.inviteNameTarget.value = ""
                this.inviteEmailTarget.value = ""
                this.searchInputTarget.value = ""
                this.searchResultsTarget.innerHTML = ""
            } else {
                alert(data.error || "Something went wrong. Please try again.")
            }
        } catch (error) {
            console.error("Invite error:", error)
            alert("Something went wrong. Please try again.")
        } finally {
            button.disabled = false
            button.textContent = originalText
        }
    }

    // --- Private helpers ---

    _captureBios() {
        if (!this.hasSelectedListTarget) return
        this.selectedListTarget.querySelectorAll('textarea[name^="instructor_bios"]').forEach(ta => {
            const match = ta.name.match(/\[(\d+)\]/)
            if (match) {
                const instructor = this.selectedInstructors.find(i => String(i.id) === match[1])
                if (instructor) instructor.bio = ta.value
            }
        })
    }

    _renderSelectedList() {
        if (!this.hasSelectedListTarget) return

        if (this.selectedInstructors.length === 0) {
            this.selectedListTarget.classList.add("hidden")
            this.selectedListTarget.innerHTML = ""
            return
        }

        const formPart = this._formAttr ? ` form="${this._formAttr}"` : ""

        this.selectedListTarget.classList.remove("hidden")
        this.selectedListTarget.innerHTML = `<label class="block text-sm font-medium text-gray-900 mb-1.5">Selected Instructors</label>` +
            this.selectedInstructors.map((instructor) => {
            const initials = instructor.name.split(" ").map(n => n[0]).join("").substring(0, 2).toUpperCase()
            const headshot = instructor.headshotUrl
                ? `<img src="${instructor.headshotUrl}" alt="${this._escapeHtml(instructor.name)}" class="w-10 h-10 rounded-lg object-cover flex-shrink-0">`
                : `<div class="w-10 h-10 rounded-lg bg-pink-100 flex items-center justify-center text-pink-700 font-bold text-xs flex-shrink-0">${initials}</div>`

            const existingHeadshotHtml = instructor.hasExistingHeadshot
                ? `<p class="text-xs text-green-600 mb-1">Alternate photo uploaded</p>`
                : ""

            return `
                <div class="border border-pink-200 bg-pink-50 rounded-lg overflow-hidden">
                    <div class="flex items-center gap-3 p-3">
                        ${headshot}
                        <div class="flex-grow min-w-0">
                            <div class="font-medium text-sm text-gray-900">${this._escapeHtml(instructor.name)}</div>
                            ${instructor.email ? `<div class="text-xs text-gray-500">${this._escapeHtml(instructor.email)}</div>` : ""}
                        </div>
                        <button type="button"
                                data-action="instructor-search#removeInstructor"
                                data-person-id="${instructor.id}"
                                class="text-gray-400 hover:text-red-500 cursor-pointer flex-shrink-0 p-1"
                                title="Remove instructor">
                            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                            </svg>
                        </button>
                    </div>
                    <div class="px-3 pb-3 pt-1 border-t border-pink-100 space-y-3">
                        <div>
                            <label class="block text-xs font-medium text-gray-700 mb-1">Alternate Photo</label>
                            ${existingHeadshotHtml}
                            <input type="file" name="instructor_headshots[${instructor.id}]" accept="image/*"${formPart}
                                   class="block w-full text-xs text-gray-500 file:mr-3 file:py-1.5 file:px-3 file:rounded-md file:border-0 file:text-xs file:font-medium file:bg-pink-50 file:text-pink-700 hover:file:bg-pink-100 cursor-pointer">
                            <p class="text-[11px] text-gray-400 mt-1">Overrides their profile photo on the registration page.</p>
                        </div>
                        <div>
                            <label class="block text-xs font-medium text-gray-700 mb-1">Bio</label>
                            <textarea name="instructor_bios[${instructor.id}]" rows="2" placeholder="Brief bio for registration page..."${formPart}
                                      class="block w-full px-2.5 py-2 text-sm bg-white border border-gray-300 rounded-md shadow-sm text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-pink-500 focus:border-pink-500 transition">${this._escapeHtml(instructor.bio)}</textarea>
                        </div>
                    </div>
                </div>
            `
        }).join("")
    }

    _updateHiddenInputs() {
        if (!this.hasPersonIdsContainerTarget) return

        const formPart = this._formAttr ? ` form="${this._formAttr}"` : ""

        this.personIdsContainerTarget.innerHTML = this.selectedInstructors.map(instructor =>
            `<input type="hidden" name="instructor_person_ids[]" value="${instructor.id}" data-name="${this._escapeHtml(instructor.name)}" data-email="${this._escapeHtml(instructor.email)}" data-headshot-url="${this._escapeHtml(instructor.headshotUrl)}"${formPart}>`
        ).join("")
    }

    _showOptionsIfNeeded() {
        const hasInstructors = this.selectedInstructors.length > 0
        if (this.hasTeamToggleSectionTarget) {
            this.teamToggleSectionTarget.classList.toggle("hidden", !hasInstructors)
            this.teamToggleSectionTarget.style.display = hasInstructors ? "" : "none"
        }
        if (this.hasInstructorOptionsSectionTarget) {
            this.instructorOptionsSectionTarget.classList.toggle("hidden", !hasInstructors)
        }
    }

    _disableAlreadySelected() {
        const selectedIds = new Set(this.selectedInstructors.map(i => String(i.id)))
        const buttons = this.searchResultsTarget.querySelectorAll("[data-action='instructor-search#selectPerson']")
        buttons.forEach(btn => {
            if (selectedIds.has(String(btn.dataset.personId))) {
                btn.disabled = true
                btn.classList.add("opacity-50", "pointer-events-none")
                btn.querySelector(".added-badge")?.remove()
                const badge = document.createElement("span")
                badge.className = "added-badge text-xs text-green-600 font-medium ml-2"
                badge.textContent = "Added"
                btn.appendChild(badge)
            }
        })
    }

    _escapeHtml(text) {
        const div = document.createElement("div")
        div.textContent = text || ""
        return div.innerHTML
    }
}
