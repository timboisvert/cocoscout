import { Controller } from "@hotwired/stimulus"

// Access by module (manage/productions/_permissions_content): template
// pills fill the None / View / Manage grid; changing a line makes it
// Custom; Save PATCHes update_access and reloads the People page.
export default class extends Controller {
  static targets = ["template", "blurb", "grid", "radio", "status", "save"]
  static values = { templates: Object, blurbs: Object, url: String, template: String }

  connect() {
    this.applyTemplate(this.templateValue, { fill: false })
  }

  pickTemplate(event) {
    this.applyTemplate(event.currentTarget.dataset.template, { fill: true })
  }

  pickLevel() {
    if (this.templateValue === "manager") return
    const current = this.currentGrants()
    const match = Object.keys(this.templatesValue).find((t) => t !== "manager" && t !== "custom" && this.same(this.templatesValue[t], current))
    this.applyTemplate(match || "custom", { fill: false })
  }

  applyTemplate(template, { fill }) {
    this.templateValue = template
    this.templateTargets.forEach((b) => {
      const on = b.dataset.template === template
      b.setAttribute("aria-pressed", on)
      b.classList.toggle("bg-pink-50", on)
      b.classList.toggle("border-pink-300", on)
      b.classList.toggle("text-pink-700", on)
      b.classList.toggle("bg-white", !on)
      b.classList.toggle("border-gray-300", !on)
      b.classList.toggle("text-gray-700", !on)
    })
    if (this.hasBlurbTarget) this.blurbTarget.textContent = this.blurbsValue[template] || ""
    if (fill && this.templatesValue[template]) {
      const grants = this.templatesValue[template]
      this.radioTargets.forEach((r) => { r.checked = grants[this.moduleOf(r)] === r.value })
    }
    const locked = template === "manager"
    this.radioTargets.forEach((r) => {
      const always = this.moduleOf(r) === "productions" && r.value === "none"
      r.disabled = locked || always
    })
    this.gridTarget.classList.toggle("opacity-60", locked)
    if (this.hasStatusTarget) this.statusTarget.textContent = ""
  }

  async save() {
    const body = { template: this.templateValue, grants: this.currentGrants() }
    this.saveTarget.disabled = true
    if (this.hasStatusTarget) this.statusTarget.textContent = "Saving…"
    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
          "X-Requested-With": "XMLHttpRequest"
        },
        body: JSON.stringify(body)
      })
      if (!response.ok) throw new Error("save failed")
      window.location.reload()
    } catch (e) {
      this.saveTarget.disabled = false
      if (this.hasStatusTarget) this.statusTarget.textContent = "That didn't save. Try again."
    }
  }

  currentGrants() {
    const grants = {}
    this.radioTargets.forEach((r) => { if (r.checked) grants[this.moduleOf(r)] = r.value })
    return grants
  }

  moduleOf(radio) {
    return radio.name.replace(/^grants\[(.+)\]$/, "$1")
  }

  same(a, b) {
    const keys = new Set([...Object.keys(a), ...Object.keys(b)])
    for (const k of keys) if ((a[k] || "none") !== (b[k] || "none")) return false
    return true
  }
}
