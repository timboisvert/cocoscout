import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "modalContent", "individualsSection", "sendToAllField", "recipientList", 
                    "productionSelect", "recipientSection", "talentPoolCount", "recipientListContent", "individualsList",
                    "subjectSection", "subjectPrefix"]

  openModal(event) {
    event.preventDefault()
    this.modalTarget.classList.remove("hidden")
    document.body.style.overflow = "hidden"
  }

  closeModal() {
    this.modalTarget.classList.add("hidden")
    document.body.style.overflow = ""
  }

  closeModalOnBackdrop(event) {
    if (event.target === this.modalTarget) {
      this.closeModal()
    }
  }

  stopPropagation(event) {
    event.stopPropagation()
  }

  toggleRecipientType(event) {
    const value = event.target.value

    if (value === "all") {
      this.individualsSectionTarget.classList.add("hidden")
      this.sendToAllFieldTarget.value = "1"
    } else {
      this.individualsSectionTarget.classList.remove("hidden")
      this.sendToAllFieldTarget.value = "0"
    }
  }

  toggleRecipientList(event) {
    event.preventDefault()
    if (this.hasRecipientListTarget) {
      this.recipientListTarget.classList.toggle("hidden")
      // Update button text
      const button = event.currentTarget
      button.textContent = this.recipientListTarget.classList.contains("hidden") ? "Show" : "Hide"
    }
  }

  async loadTalentPool(event) {
    const productionId = event.target.value
    const selectedOption = event.target.options[event.target.selectedIndex]
    const productionName = selectedOption ? selectedOption.text : ''
    
    if (!productionId) {
      // Hide sections if no production selected
      if (this.hasRecipientSectionTarget) {
        this.recipientSectionTarget.classList.add("hidden")
      }
      if (this.hasSubjectSectionTarget) {
        this.subjectSectionTarget.classList.add("hidden")
      }
      return
    }

    try {
      const response = await fetch(`/manage/communications/talent_pool_members/${productionId}`)
      const data = await response.json()
      
      // Show recipient section
      if (this.hasRecipientSectionTarget) {
        this.recipientSectionTarget.classList.remove("hidden")
      }
      
      // Show subject section and update prefix
      if (this.hasSubjectSectionTarget) {
        this.subjectSectionTarget.classList.remove("hidden")
      }
      if (this.hasSubjectPrefixTarget) {
        this.subjectPrefixTarget.textContent = `[${productionName}]`
      }
      
      // Update count
      if (this.hasTalentPoolCountTarget) {
        this.talentPoolCountTarget.textContent = data.people.length
      }
      
      // Update recipient list (read-only display)
      if (this.hasRecipientListContentTarget) {
        if (data.people.length === 0) {
          this.recipientListContentTarget.innerHTML = '<div class="text-gray-500">No members in talent pool</div>'
        } else {
          this.recipientListContentTarget.innerHTML = data.people.map(p => 
            `<div class="text-gray-600">${this.escapeHtml(p.name)}</div>`
          ).join('')
        }
      }
      
      // Update individuals checkboxes
      if (this.hasIndividualsListTarget) {
        if (data.people.length === 0) {
          this.individualsListTarget.innerHTML = '<div class="text-gray-500 text-sm">No members in talent pool</div>'
        } else {
          this.individualsListTarget.innerHTML = data.people.map(p => 
            `<label class="flex items-center cursor-pointer">
              <input type="checkbox" name="person_ids[]" value="${p.id}" class="mr-2 accent-pink-500 cursor-pointer">
              <span class="text-sm">${this.escapeHtml(p.name)}</span>
            </label>`
          ).join('')
        }
      }
    } catch (error) {
      console.error('Failed to load talent pool members:', error)
    }
  }

  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}
