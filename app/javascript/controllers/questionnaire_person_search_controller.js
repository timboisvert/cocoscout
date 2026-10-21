import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["selectedList", "hiddenFields"]

    connect() {
        this.selectedIds = new Set()
    }

    // people-picker:pick from the shared People Picker ("questionnaire-picker"):
    // each tap adds a chip and a person_ids[] field for the invitation form.
    picked(event) {
        const pick = event.detail
        if (pick.picker !== "questionnaire-picker" || pick.type !== "Person") return
        this.add(pick.id, pick.name, pick.initials, pick.headshotUrl || "")
    }


    add(id, name, initials, headshot) {
        id = parseInt(id)
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
