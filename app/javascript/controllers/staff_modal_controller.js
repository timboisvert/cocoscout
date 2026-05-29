import { Controller } from "@hotwired/stimulus"

// Drives the Add/Edit Staff modal on /manage/staffing/staff.
// Two modes:
//   - new: pick a person from the org (via the inner picker modal),
//          then check role qualifications
//   - edit: person is fixed; only the role checkboxes are editable
//
// Inner "Pick a person" modal does client-side fuzzy search of the org's
// people. Available people are passed in via a JSON blob (not a server
// endpoint — fine for typical org sizes).
export default class extends Controller {
    static targets = [
        "modal", "form", "title", "submitButton", "methodInput",
        "personIdInput", "personRow", "personAvatar", "personName", "personEmail",
        "pickerModal", "pickerSearch", "pickerResults",
        "roleCheckbox",
        "inviteNameInput", "inviteEmailInput",
        "inviteForm", "inviteName", "inviteEmail", "inviteError"
    ]
    static values = {
        createUrl: String,
        updateUrlTemplate: String,
        availablePeople: Array
    }

    openForNew(event) {
        if (event) event.preventDefault()
        this.resetForm()
        if (this.hasFormTarget && this.hasCreateUrlValue) {
            this.formTarget.action = this.createUrlValue
        }
        if (this.hasMethodInputTarget) this.methodInputTarget.value = "post"
        if (this.hasTitleTarget) this.titleTarget.textContent = "Add staff member"
        this.setSubmitText("Add staff member")
        if (this.hasSubmitButtonTarget) this.submitButtonTarget.disabled = true
        this.showPersonRow(null)
        this.show()
    }

    openForEdit(event) {
        if (event) event.preventDefault()
        this.clearInvite()
        const btn = event.currentTarget
        const memberId = btn.dataset.memberId
        const personName = btn.dataset.personName
        const personEmail = btn.dataset.personEmail
        const headshotUrl = btn.dataset.personHeadshotUrl
        const personInitials = btn.dataset.personInitials
        let roleIds = []
        try { roleIds = JSON.parse(btn.dataset.memberRoleIds || "[]") } catch (_) {}

        if (this.hasFormTarget && this.hasUpdateUrlTemplateValue) {
            this.formTarget.action = this.updateUrlTemplateValue.replace(":id", memberId)
        }
        if (this.hasMethodInputTarget) this.methodInputTarget.value = "patch"
        if (this.hasTitleTarget) this.titleTarget.textContent = "Edit staff member"
        this.setSubmitText("Save changes")
        if (this.hasSubmitButtonTarget) this.submitButtonTarget.disabled = false

        // Person is fixed for edit
        this.showPersonRow({ name: personName, email: personEmail, headshotUrl, initials: personInitials, locked: true })

        // Check the right role boxes
        this.roleCheckboxTargets.forEach(cb => {
            cb.checked = roleIds.includes(parseInt(cb.value, 10))
        })

        this.show()
    }

    close(event) {
        if (event) event.preventDefault()
        this.hide()
    }

    backdropClose(event) {
        if (event.target === this.modalTarget) this.hide()
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    // ----- Inner picker -----

    openPicker(event) {
        if (event) event.preventDefault()
        if (!this.hasPickerModalTarget) return
        if (this.hasPickerSearchTarget) {
            this.pickerSearchTarget.value = ""
            this.renderPickerResults("")
        }
        this.hideInviteForm()
        this.pickerModalTarget.classList.remove("hidden")
        setTimeout(() => this.pickerSearchTarget?.focus(), 50)
    }

    // ----- Invite a brand-new person -----

    showInviteForm(event) {
        if (event) event.preventDefault()
        if (this.hasInviteFormTarget) this.inviteFormTarget.classList.remove("hidden")
        if (this.hasInviteErrorTarget) this.inviteErrorTarget.classList.add("hidden")
        setTimeout(() => this.inviteNameTarget?.focus(), 50)
    }

    hideInviteForm() {
        if (this.hasInviteFormTarget) this.inviteFormTarget.classList.add("hidden")
        if (this.hasInviteNameTarget) this.inviteNameTarget.value = ""
        if (this.hasInviteEmailTarget) this.inviteEmailTarget.value = ""
        if (this.hasInviteErrorTarget) this.inviteErrorTarget.classList.add("hidden")
    }

    confirmInvite(event) {
        if (event) event.preventDefault()
        const name = (this.hasInviteNameTarget ? this.inviteNameTarget.value : "").trim()
        const email = (this.hasInviteEmailTarget ? this.inviteEmailTarget.value : "").trim()

        if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
            if (this.hasInviteErrorTarget) {
                this.inviteErrorTarget.textContent = "Enter a valid email address."
                this.inviteErrorTarget.classList.remove("hidden")
            }
            return
        }

        // Inviting replaces the existing-person selection.
        if (this.hasPersonIdInputTarget) this.personIdInputTarget.value = ""
        if (this.hasInviteNameInputTarget) this.inviteNameInputTarget.value = name
        if (this.hasInviteEmailInputTarget) this.inviteEmailInputTarget.value = email

        this.showPersonRow({
            name: name || email,
            email: email,
            initials: (name || email)[0]?.toUpperCase() || "?",
            locked: false,
            invited: true
        })
        if (this.hasSubmitButtonTarget) this.submitButtonTarget.disabled = false
        this.setSubmitText("Send invite & add")
        this.closePicker()
    }

    clearInvite() {
        if (this.hasInviteNameInputTarget) this.inviteNameInputTarget.value = ""
        if (this.hasInviteEmailInputTarget) this.inviteEmailInputTarget.value = ""
        this.hideInviteForm()
    }

    closePicker(event) {
        if (event) event.preventDefault()
        if (this.hasPickerModalTarget) this.pickerModalTarget.classList.add("hidden")
    }

    pickerBackdropClose(event) {
        if (event.target === this.pickerModalTarget) this.closePicker(event)
    }

    pickerSearchInput() {
        this.renderPickerResults(this.pickerSearchTarget.value.trim())
    }

    // Triggered from a result row (inline data-action on each result button).
    selectPerson(event) {
        if (event) event.preventDefault()
        const btn = event.currentTarget
        const id = btn.dataset.personId
        const person = this.availablePeopleValue.find(p => String(p.id) === String(id))
        if (!person) return
        if (this.hasPersonIdInputTarget) this.personIdInputTarget.value = person.id
        if (this.hasSubmitButtonTarget) this.submitButtonTarget.disabled = false
        this.showPersonRow({ name: person.name, email: person.email, headshotUrl: person.headshot_url, initials: person.initials, locked: false })
        this.closePicker()
    }

    clearPerson(event) {
        if (event) event.preventDefault()
        if (this.hasPersonIdInputTarget) this.personIdInputTarget.value = ""
        this.clearInvite()
        if (this.hasSubmitButtonTarget) this.submitButtonTarget.disabled = true
        this.setSubmitText("Add staff member")
        this.showPersonRow(null)
    }

    // ----- private -----

    showPersonRow(person) {
        if (!this.hasPersonRowTarget) return
        if (!person) {
            // Empty state — show the "click to add someone" placeholder
            this.personRowTarget.innerHTML = `
                <button type="button"
                        data-action="click->staff-modal#openPicker"
                        class="w-full flex items-center justify-center gap-2 p-3 border-2 border-dashed border-gray-300 rounded-lg text-gray-400 text-sm hover:border-pink-400 hover:bg-pink-50 hover:text-pink-600 transition-all cursor-pointer">
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" class="w-4 h-4">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
                    </svg>
                    Click to add someone
                </button>`
            return
        }
        const avatar = person.headshotUrl
            ? `<img src="${this.escapeHtml(person.headshotUrl)}" alt="${this.escapeHtml(person.name)}" class="w-10 h-10 rounded-lg object-cover flex-shrink-0">`
            : `<div class="w-10 h-10 rounded-lg bg-gray-200 flex items-center justify-center text-gray-600 font-bold text-sm flex-shrink-0">${this.escapeHtml(person.initials || person.name?.[0]?.toUpperCase() || "?")}</div>`
        const removeBtn = person.locked ? "" : `
            <button type="button" data-action="click->staff-modal#clearPerson" class="text-sm text-gray-500 hover:text-pink-600 underline cursor-pointer bg-transparent border-0 p-0">Change</button>`
        const invitedBadge = person.invited
            ? `<span class="inline-flex items-center px-1.5 py-0.5 rounded bg-amber-100 text-amber-700 text-[10px] font-medium ml-1">Will be invited</span>`
            : ""
        this.personRowTarget.innerHTML = `
            <div class="flex items-center gap-3 p-3 bg-gray-50 border border-gray-200 rounded-lg">
                ${avatar}
                <div class="flex-1 min-w-0">
                    <div class="font-medium text-gray-900 truncate">${this.escapeHtml(person.name)}${invitedBadge}</div>
                    ${person.email ? `<div class="text-xs text-gray-500 truncate">${this.escapeHtml(person.email)}</div>` : ""}
                </div>
                ${removeBtn}
            </div>`
    }

    renderPickerResults(query) {
        if (!this.hasPickerResultsTarget) return
        const q = query.toLowerCase()
        const people = this.availablePeopleValue
        const matches = q.length === 0
            ? people.slice(0, 50)
            : people.filter(p =>
                (p.name || "").toLowerCase().includes(q) ||
                (p.email || "").toLowerCase().includes(q)
              ).slice(0, 50)

        if (matches.length === 0) {
            this.pickerResultsTarget.innerHTML = `<p class="text-sm text-gray-400 text-center py-6">No people found.</p>`
            return
        }

        const html = matches.map(p => {
            const avatar = p.headshot_url
                ? `<img src="${this.escapeHtml(p.headshot_url)}" class="w-8 h-8 rounded-lg object-cover flex-shrink-0" alt="">`
                : `<div class="w-8 h-8 rounded-lg bg-gray-200 flex items-center justify-center text-gray-600 font-bold text-xs flex-shrink-0">${this.escapeHtml(p.initials || (p.name?.[0]?.toUpperCase() || "?"))}</div>`
            return `
                <button type="button"
                        data-person-id="${p.id}"
                        data-action="click->staff-modal#selectPerson"
                        class="w-full flex items-center gap-3 p-2 rounded hover:bg-pink-50 cursor-pointer text-left transition-colors">
                    ${avatar}
                    <div class="flex-1 min-w-0">
                        <div class="text-sm font-medium text-gray-900 truncate">${this.escapeHtml(p.name || "(no name)")}</div>
                        ${p.email ? `<div class="text-xs text-gray-500 truncate">${this.escapeHtml(p.email)}</div>` : ""}
                    </div>
                </button>`
        }).join("")
        this.pickerResultsTarget.innerHTML = html
    }

    show()   { if (this.hasModalTarget) this.modalTarget.classList.remove("hidden") }
    hide()   { if (this.hasModalTarget) this.modalTarget.classList.add("hidden") }

    resetForm() {
        if (this.hasPersonIdInputTarget) this.personIdInputTarget.value = ""
        this.clearInvite()
        this.roleCheckboxTargets.forEach(cb => { cb.checked = false })
    }

    setSubmitText(text) {
        if (!this.hasSubmitButtonTarget) return
        const span = this.submitButtonTarget.querySelector("span")
        if (span) span.textContent = text
    }

    escapeHtml(str) {
        if (str == null) return ""
        const div = document.createElement("div")
        div.textContent = String(str)
        return div.innerHTML
    }
}
