import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "personIdsContainer", "fileInputsContainer", "ogImageSourceInput",
    "selectedList",
    "addModal", "selfSelectLabel", "searchInput", "searchResults", "inviteSection", "inviteNameInput", "inviteEmailInput",
    "editModal", "editModalTitle", "editModalHeadshotSlot", "editModalFileZone",
    "editModalShareSection", "editModalShareCheckbox",
    "groupPhotoSection", "groupPhotoInputSection", "groupBioInputSection",
    "groupShareCheckbox",
    "displayOptionsSection", "showGroupPhotoOption", "showGroupBioOption",
    "productionTeamSection",
  ]

  static values = {
    searchUrl: String, inviteUrl: String,
    currentPersonId: String, currentPersonName: String,
    currentPersonEmail: String, currentPersonHeadshotUrl: String,
  }

  connect() {
    this.selectedInstructors = []
    this.editingPersonId = null
    this._formAttr = ""
    this._searchTimer = null

    if (this.hasPersonIdsContainerTarget) {
      this.personIdsContainerTarget.querySelectorAll('input[name="instructor_person_ids[]"]').forEach(input => {
        if (!this._formAttr && input.getAttribute("form")) this._formAttr = input.getAttribute("form")
        this.selectedInstructors.push({
          id: input.value,
          name: input.dataset.name || "",
          email: input.dataset.email || "",
          headshotUrl: input.dataset.headshotUrl || "",
          existingHeadshotUrl: input.dataset.existingHeadshotUrl || "",
        })
      })
    }

    this._renderList()
    this._updateSections()
  }

  // ── Add modal ──────────────────────────────────────────────────

  openAddModal(e) {
    e.preventDefault()
    if (this.hasSelfSelectLabelTarget) {
      const hasInstructors = this.selectedInstructors.length > 0
      this.selfSelectLabelTarget.textContent = hasInstructors ? "I'm also one of the instructors" : "I'm the instructor"
    }
    this.addModalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
    setTimeout(() => this.hasSearchInputTarget && this.searchInputTarget.focus(), 50)
  }

  closeAddModal(e) {
    e?.preventDefault()
    this.addModalTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
    if (this.hasSearchInputTarget) this.searchInputTarget.value = ""
    if (this.hasSearchResultsTarget) this.searchResultsTarget.innerHTML = ""
    if (this.hasInviteSectionTarget) this.inviteSectionTarget.classList.add("hidden")
  }

  // ── Edit modal ─────────────────────────────────────────────────

  openEditModal(e) {
    e.preventDefault?.()
    const id = String(e.currentTarget?.dataset?.personId || "")
    if (!id) return
    const inst = this.selectedInstructors.find(i => i.id === id)
    if (!inst) return

    this.editingPersonId = id

    // Header
    const initials = inst.name.split(" ").filter(Boolean).map(n => n[0]).join("").slice(0, 2).toUpperCase()
    const photo = inst.existingHeadshotUrl || inst.headshotUrl
    this.editModalHeadshotSlotTarget.innerHTML = photo
      ? `<img src="${this._esc(photo)}" class="w-12 h-12 rounded-lg object-cover" alt="">`
      : `<div class="w-12 h-12 rounded-lg bg-pink-100 flex items-center justify-center text-pink-700 font-bold text-sm">${initials}</div>`
    this.editModalTitleTarget.textContent = inst.name

    // Move instructor inputs div into modal
    const div = document.getElementById(`instructor-inputs-${id}`)
    if (div && this.hasEditModalFileZoneTarget) {
      this.editModalFileZoneTarget.appendChild(div)
      // Wire file→preview
      const fileInput = div.querySelector('input[type="file"]')
      const preview = div.querySelector("[data-photo-preview]")
      if (fileInput && preview) {
        fileInput.onchange = () => {
          const file = fileInput.files[0]
          if (!file) return
          const reader = new FileReader()
          reader.onload = ev => { preview.src = ev.target.result; preview.classList.remove("hidden") }
          reader.readAsDataURL(file)
        }
      }
    }

    // Share image section — only for 2+ instructors
    if (this.hasEditModalShareSectionTarget) {
      const multi = this.selectedInstructors.length >= 2
      this.editModalShareSectionTarget.classList.toggle("hidden", !multi)
      if (multi && this.hasEditModalShareCheckboxTarget) {
        const src = this.hasOgImageSourceInputTarget ? this.ogImageSourceInputTarget.value : "auto"
        this.editModalShareCheckboxTarget.checked = src === id
      }
    }

    this.editModalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  saveEditModal(e) {
    e?.preventDefault()
    if (!this.editingPersonId) return
    const id = this.editingPersonId

    // Persist share choice to hidden input
    if (this.hasEditModalShareSectionTarget && !this.editModalShareSectionTarget.classList.contains("hidden") &&
        this.hasEditModalShareCheckboxTarget) {
      const src = this.hasOgImageSourceInputTarget ? this.ogImageSourceInputTarget.value : "auto"
      if (this.editModalShareCheckboxTarget.checked) {
        this._setOgSource(id)
      } else if (src === id) {
        this._setOgSource("auto")
      }
    }

    // Update local preview from newly selected file (for compact row)
    const div = document.getElementById(`instructor-inputs-${id}`)
    const fileInput = div?.querySelector('input[type="file"]')
    const inst = this.selectedInstructors.find(i => i.id === id)
    if (fileInput?.files?.[0] && inst) {
      inst.existingHeadshotUrl = URL.createObjectURL(fileInput.files[0])
    }

    this._returnInputsDiv(id)
    this._closeEditModal()
    this._renderList()
  }

  cancelEditModal(e) {
    e?.preventDefault()
    this._returnInputsDiv(this.editingPersonId)
    this._closeEditModal()
  }

  _returnInputsDiv(id) {
    if (!id || !this.hasFileInputsContainerTarget) return
    const div = document.getElementById(`instructor-inputs-${id}`)
    if (div) this.fileInputsContainerTarget.appendChild(div)
  }

  _closeEditModal() {
    if (this.hasEditModalTarget) {
      this.editModalTarget.classList.add("hidden")
      document.body.classList.remove("overflow-hidden")
    }
    if (this.hasEditModalFileZoneTarget) this.editModalFileZoneTarget.innerHTML = ""
    this.editingPersonId = null
  }

  // ── Group photo / bio ──────────────────────────────────────────

  toggleGroupPhotoInput(e) {
    const show = e.target.checked
    if (this.hasGroupPhotoInputSectionTarget) this.groupPhotoInputSectionTarget.classList.toggle("hidden", !show)
    if (this.hasShowGroupPhotoOptionTarget) this.showGroupPhotoOptionTarget.classList.toggle("hidden", !show)
    if (!show) {
      const src = this.hasOgImageSourceInputTarget ? this.ogImageSourceInputTarget.value : "auto"
      if (src === "group_photo") this._setOgSource("auto")
    }
  }

  toggleGroupBioInput(e) {
    const show = e.target.checked
    if (this.hasGroupBioInputSectionTarget) this.groupBioInputSectionTarget.classList.toggle("hidden", !show)
    if (this.hasShowGroupBioOptionTarget) this.showGroupBioOptionTarget.classList.toggle("hidden", !show)
  }

  onGroupPhotoChange(e) {
    const file = e.target.files?.[0]
    if (!file) return
    const section = e.target.closest("[data-group-photo-section]") || this.element
    const preview = section.querySelector("[data-group-photo-preview]")
    if (preview) {
      const reader = new FileReader()
      reader.onload = ev => { preview.src = ev.target.result; preview.classList.remove("hidden") }
      reader.readAsDataURL(file)
    }
  }

  onGroupBioChange(e) {
    const has = e.target.value.trim().length > 0
    if (this.hasShowGroupBioOptionTarget) this.showGroupBioOptionTarget.classList.toggle("hidden", !has)
  }

  toggleGroupShare(e) {
    this._setOgSource(e.target.checked ? "group_photo" : "auto")
    this._renderList()
  }

  // ── Search ─────────────────────────────────────────────────────

  search() {
    clearTimeout(this._searchTimer)
    this._searchTimer = setTimeout(() => this._doSearch(), 250)
  }

  async _doSearch() {
    const q = this.searchInputTarget.value.trim()
    if (q.length < 2) {
      this.searchResultsTarget.innerHTML = `<p class="text-sm text-gray-400 px-1 py-2">Type at least 2 characters to search...</p>`
      return
    }
    this.searchResultsTarget.innerHTML = `<div class="flex justify-center py-4"><div class="animate-spin rounded-full h-5 w-5 border-b-2 border-pink-500"></div></div>`
    try {
      const r = await fetch(`${this.searchUrlValue}?q=${encodeURIComponent(q)}`, {
        headers: { Accept: "text/html", "X-Requested-With": "XMLHttpRequest" }
      })
      if (r.ok) { this.searchResultsTarget.innerHTML = await r.text(); this._disableSelected() }
      else this.searchResultsTarget.innerHTML = `<p class="text-sm text-red-500 px-1 py-2">Error searching.</p>`
    } catch { this.searchResultsTarget.innerHTML = `<p class="text-sm text-red-500 px-1 py-2">Error searching.</p>` }
  }

  selectSelf(e) {
    e.preventDefault()
    if (!this.currentPersonIdValue) return
    if (this.selectedInstructors.some(i => i.id === this.currentPersonIdValue)) return
    this._addAndEdit({ id: this.currentPersonIdValue, name: this.currentPersonNameValue, email: this.currentPersonEmailValue, headshotUrl: this.currentPersonHeadshotUrlValue, existingHeadshotUrl: "" })
  }

  selectPerson(e) {
    e.preventDefault()
    const { personId: id, personName: name, personEmail: email = "", personHeadshotUrl: headshotUrl = "" } = e.currentTarget.dataset
    if (!id || this.selectedInstructors.some(i => i.id === id)) return
    this._addAndEdit({ id, name, email, headshotUrl, existingHeadshotUrl: "" })
  }

  _addAndEdit(inst) {
    this.selectedInstructors.push(inst)
    this._createInputsDiv(inst.id)
    this._updateHiddenInputs()
    this._renderList()
    this._updateSections()
    this.closeAddModal()
    this.openEditModal({ preventDefault: () => {}, currentTarget: { dataset: { personId: inst.id } } })
  }

  removeInstructor(e) {
    e.preventDefault()
    const id = String(e.currentTarget.dataset.personId)
    const src = this.hasOgImageSourceInputTarget ? this.ogImageSourceInputTarget.value : "auto"
    if (src === id) this._setOgSource("auto")
    this.selectedInstructors = this.selectedInstructors.filter(i => i.id !== id)
    document.getElementById(`instructor-inputs-${id}`)?.remove()
    this._updateHiddenInputs()
    this._renderList()
    this._updateSections()
  }

  showInviteForm(e) {
    e.preventDefault()
    if (this.hasInviteSectionTarget) this.inviteSectionTarget.classList.remove("hidden")
  }

  async invitePerson(e) {
    e.preventDefault()
    const name = this.inviteNameInputTarget?.value.trim()
    const email = this.inviteEmailInputTarget?.value.trim()
    if (!name || !email) { alert("Please enter both name and email."); return }
    const btn = e.currentTarget
    btn.disabled = true; const orig = btn.textContent; btn.textContent = "Sending..."
    try {
      const r = await fetch(this.inviteUrlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content },
        body: JSON.stringify({ name, email })
      })
      const data = await r.json()
      if (data.success) {
        this._addAndEdit({ id: String(data.person_id), name, email, headshotUrl: "", existingHeadshotUrl: "" })
      } else { alert(data.error || "Something went wrong.") }
    } catch { alert("Something went wrong.") }
    finally { btn.disabled = false; btn.textContent = orig }
  }

  // ── Share icon on compact row ──────────────────────────────────

  toggleShare(e) {
    e.preventDefault()
    const id = e.currentTarget.dataset.personId
    const src = this.hasOgImageSourceInputTarget ? this.ogImageSourceInputTarget.value : "auto"
    this._setOgSource(src === id ? "auto" : id)
    this._renderList()
  }

  // ── Private ────────────────────────────────────────────────────

  _setOgSource(val) {
    if (this.hasOgImageSourceInputTarget) this.ogImageSourceInputTarget.value = val
    if (this.hasGroupShareCheckboxTarget) this.groupShareCheckboxTarget.checked = val === "group_photo"
  }

  _createInputsDiv(id) {
    if (!this.hasFileInputsContainerTarget) return
    const f = this._formAttr ? ` form="${this._formAttr}"` : ""
    const div = document.createElement("div")
    div.id = `instructor-inputs-${id}`
    div.className = "space-y-4"
    div.innerHTML = `
      <div>
        <label class="block text-sm font-medium text-gray-700 mb-1.5">Photo Override</label>
        <img data-photo-preview class="hidden w-16 h-16 rounded-lg object-cover mb-2" alt="">
        <input type="file" name="instructor_headshots[${id}]" accept="image/*"${f}
               class="block w-full text-sm text-gray-500 file:mr-3 file:py-1.5 file:px-3 file:rounded-md file:border-0 file:text-sm file:font-medium file:bg-pink-50 file:text-pink-700 hover:file:bg-pink-100 cursor-pointer">
        <p class="text-xs text-gray-400 mt-1">Overrides their CocoScout profile photo on the registration page.</p>
      </div>
      <div>
        <label class="block text-sm font-medium text-gray-700 mb-1.5">Bio</label>
        <textarea name="instructor_bios[${id}]" rows="5"${f}
                  class="block w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-pink-500 focus:border-pink-500 resize-none"
                  placeholder="Write a short bio for this instructor..."></textarea>
      </div>`
    this.fileInputsContainerTarget.appendChild(div)
  }

  _updateHiddenInputs() {
    if (!this.hasPersonIdsContainerTarget) return
    const f = this._formAttr ? ` form="${this._formAttr}"` : ""
    this.personIdsContainerTarget.innerHTML = this.selectedInstructors.map(i =>
      `<input type="hidden" name="instructor_person_ids[]" value="${i.id}" data-name="${this._esc(i.name)}" data-email="${this._esc(i.email)}" data-headshot-url="${this._esc(i.headshotUrl)}" data-existing-headshot-url="${this._esc(i.existingHeadshotUrl)}"${f}>`
    ).join("")
  }

  _renderList() {
    if (!this.hasSelectedListTarget) return
    const ogSrc = this.hasOgImageSourceInputTarget ? this.ogImageSourceInputTarget.value : "auto"
    const multi = this.selectedInstructors.length >= 2

    if (!this.selectedInstructors.length) {
      this.selectedListTarget.innerHTML = `<p class="text-sm text-gray-400 italic py-1">No instructors added yet.</p>`
      return
    }

    this.selectedListTarget.innerHTML = this.selectedInstructors.map(inst => {
      const initials = inst.name.split(" ").filter(Boolean).map(n => n[0]).join("").slice(0, 2).toUpperCase()
      const photo = inst.existingHeadshotUrl || inst.headshotUrl
      const img = photo
        ? `<img src="${this._esc(photo)}" class="w-10 h-10 rounded-lg object-cover flex-shrink-0" alt="">`
        : `<div class="w-10 h-10 rounded-lg bg-pink-100 flex items-center justify-center text-pink-700 font-bold text-xs flex-shrink-0">${initials}</div>`

      const isShare = multi && ogSrc === inst.id
      const shareBtn = multi ? `
        <button type="button" data-action="instructor-search#toggleShare" data-person-id="${inst.id}"
                class="flex-shrink-0 p-1.5 rounded-md transition-colors ${isShare ? "bg-pink-50 text-pink-500" : "text-gray-300 hover:text-pink-400 hover:bg-pink-50"}"
                title="${isShare ? "Course share image — click to unset" : "Set as course share image"}">
          <svg class="w-4 h-4" fill="${isShare ? "currentColor" : "none"}" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.684 13.342C8.886 12.938 9 12.482 9 12c0-.482-.114-.938-.316-1.342m0 2.684a3 3 0 110-2.684m0 2.684l6.632 3.316m-6.632-6l6.632-3.316m0 0a3 3 0 105.367-2.684 3 3 0 00-5.367 2.684zm0 9.316a3 3 0 105.368 2.684 3 3 0 00-5.368-2.684z"/>
          </svg>
        </button>` : ""

      return `
        <div class="flex items-center gap-3 px-3 py-2.5 bg-white border border-gray-200 rounded-lg hover:border-gray-300 transition-colors">
          ${img}
          <div class="flex-grow min-w-0">
            <div class="text-sm font-medium text-gray-900 truncate">${this._esc(inst.name)}</div>
            ${inst.email ? `<div class="text-xs text-gray-400 truncate">${this._esc(inst.email)}</div>` : ""}
          </div>
          ${shareBtn}
          <button type="button" data-action="instructor-search#openEditModal" data-person-id="${inst.id}"
                  class="flex-shrink-0 px-2.5 py-1 text-xs font-medium text-gray-600 bg-gray-100 hover:bg-gray-200 rounded-md transition-colors cursor-pointer">
            Edit
          </button>
          <button type="button" data-action="instructor-search#removeInstructor" data-person-id="${inst.id}"
                  class="flex-shrink-0 p-1.5 text-gray-300 hover:text-red-500 transition-colors cursor-pointer" title="Remove">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
            </svg>
          </button>
        </div>`
    }).join("")
  }

  _updateSections() {
    const n = this.selectedInstructors.length
    if (this.hasProductionTeamSectionTarget) this.productionTeamSectionTarget.classList.toggle("hidden", n < 1)
    if (this.hasGroupPhotoSectionTarget) this.groupPhotoSectionTarget.classList.toggle("hidden", n < 2)
    if (this.hasDisplayOptionsSectionTarget) this.displayOptionsSectionTarget.classList.toggle("hidden", n < 2)
    // If dropped below 2 instructors, clear person-ID based og_image_source
    if (n < 2 && this.hasOgImageSourceInputTarget) {
      const src = this.ogImageSourceInputTarget.value
      if (src && src !== "auto" && src !== "group_photo" && src !== "none") this._setOgSource("auto")
    }
  }

  _disableSelected() {
    if (!this.hasSearchResultsTarget) return
    const ids = new Set(this.selectedInstructors.map(i => i.id))
    this.searchResultsTarget.querySelectorAll("[data-action='instructor-search#selectPerson']").forEach(btn => {
      if (ids.has(btn.dataset.personId)) { btn.disabled = true; btn.classList.add("opacity-50", "pointer-events-none") }
    })
  }

  _esc(t) { const d = document.createElement("div"); d.textContent = t || ""; return d.innerHTML }
}
