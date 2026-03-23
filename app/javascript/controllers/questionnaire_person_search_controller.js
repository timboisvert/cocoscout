import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["input", "dropdown", "selectedList", "hiddenFields"]

    connect() {
        this.people = JSON.parse(this.element.dataset.people || "[]")
        this.selectedIds = new Set()
        this.clickOutside = this.closeDropdown.bind(this)
        document.addEventListener("click", this.clickOutside)
    }

    disconnect() {
        document.removeEventListener("click", this.clickOutside)
    }

    search() {
        const query = this.inputTarget.value.trim().toLowerCase()
        if (query.length < 1) {
            this.dropdownTarget.classList.add("hidden")
            this.dropdownTarget.innerHTML = ""
            return
        }

        const matches = this.people
            .filter(p => !this.selectedIds.has(p.id) && (
                p.name.toLowerCase().includes(query) ||
                (p.email && p.email.toLowerCase().includes(query))
            ))
            .slice(0, 10)

        if (matches.length === 0) {
            this.dropdownTarget.innerHTML = `<div class="px-3 py-2 text-sm text-gray-500">No matches</div>`
        } else {
            this.dropdownTarget.innerHTML = matches.map(p => `
        <button type="button"
          class="w-full text-left px-3 py-2 hover:bg-pink-50 flex items-center gap-3 cursor-pointer"
          data-action="click->questionnaire-person-search#select"
          data-person-id="${p.id}"
          data-person-name="${this.escapeHtml(p.name)}"
          data-person-email="${this.escapeHtml(p.email || "")}"
          data-person-initials="${this.escapeHtml(p.initials)}"
          data-person-headshot="${this.escapeHtml(p.headshot || "")}">
          ${this.avatarHtml(p)}
          <div class="min-w-0">
            <div class="text-sm font-medium text-gray-900 truncate">${this.escapeHtml(p.name)}</div>
            ${p.email ? `<div class="text-xs text-gray-500 truncate">${this.escapeHtml(p.email)}</div>` : ""}
          </div>
        </button>
      `).join("")
        }

        this.dropdownTarget.classList.remove("hidden")
    }

    select(event) {
        const btn = event.currentTarget
        const id = parseInt(btn.dataset.personId)
        const name = btn.dataset.personName
        const initials = btn.dataset.personInitials
        const headshot = btn.dataset.personHeadshot

        if (this.selectedIds.has(id)) return
        this.selectedIds.add(id)

        // Add chip
        const chip = document.createElement("div")
        chip.className = "flex items-center gap-2 px-3 py-1.5 bg-pink-50 border border-pink-200 rounded-lg text-sm"
        chip.dataset.personId = id
        chip.innerHTML = `
      ${this.chipAvatarHtml(initials, headshot, name)}
      <span class="text-gray-900 font-medium">${this.escapeHtml(name)}</span>
      <button type="button" class="text-gray-400 hover:text-red-500 ml-1 cursor-pointer" data-action="click->questionnaire-person-search#remove" data-person-id="${id}">
        <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    `
        this.selectedListTarget.appendChild(chip)

        // Add hidden field
        const hidden = document.createElement("input")
        hidden.type = "hidden"
        hidden.name = "person_ids[]"
        hidden.value = id
        hidden.dataset.personId = id
        this.hiddenFieldsTarget.appendChild(hidden)

        // Clear and close
        this.inputTarget.value = ""
        this.dropdownTarget.classList.add("hidden")
        this.inputTarget.focus()
    }

    remove(event) {
        const id = parseInt(event.currentTarget.dataset.personId)
        this.selectedIds.delete(id)

        // Remove chip
        const chip = this.selectedListTarget.querySelector(`[data-person-id="${id}"]`)
        if (chip) chip.remove()

        // Remove hidden field
        const hidden = this.hiddenFieldsTarget.querySelector(`input[data-person-id="${id}"]`)
        if (hidden) hidden.remove()
    }

    closeDropdown(event) {
        if (!this.element.contains(event.target)) {
            this.dropdownTarget.classList.add("hidden")
        }
    }

    avatarHtml(person) {
        if (person.headshot) {
            return `<img src="${this.escapeHtml(person.headshot)}" alt="${this.escapeHtml(person.name)}" class="w-8 h-8 rounded-lg object-cover flex-shrink-0">`
        }
        return `<div class="w-8 h-8 rounded-lg bg-pink-100 flex items-center justify-center text-pink-600 font-bold text-xs flex-shrink-0">${this.escapeHtml(person.initials)}</div>`
    }

    chipAvatarHtml(initials, headshot, name) {
        if (headshot) {
            return `<img src="${this.escapeHtml(headshot)}" alt="${this.escapeHtml(name)}" class="w-5 h-5 rounded object-cover">`
        }
        return `<div class="w-5 h-5 rounded bg-pink-100 flex items-center justify-center text-pink-600 font-bold" style="font-size:0.5rem">${this.escapeHtml(initials)}</div>`
    }

    escapeHtml(str) {
        const div = document.createElement("div")
        div.textContent = str
        return div.innerHTML
    }
}
