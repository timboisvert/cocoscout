import { Controller } from "@hotwired/stimulus"

// Migration plan picker. Two independent toggles:
//
//   org choice:        existing | new
//   production choice: new      | existing
//
// Each toggle reveals/hides the corresponding inputs.
export default class extends Controller {
  static targets = [
    "orgChoice", "orgExistingBlock", "orgNewBlock",
    "prodChoice", "prodNewBlock", "prodExistingBlock"
  ]

  connect() { this.refresh() }

  refresh() {
    const orgChoice  = this.choice(this.orgChoiceTargets)
    const prodChoice = this.choice(this.prodChoiceTargets)

    this.toggle(this.orgExistingBlockTarget, orgChoice === "existing")
    this.toggle(this.orgNewBlockTarget,      orgChoice === "new")
    this.toggle(this.prodNewBlockTarget,      prodChoice === "new")
    this.toggle(this.prodExistingBlockTarget, prodChoice === "existing")
  }

  // Reload the page when the producer picks a different existing org —
  // so the production list refreshes server-side without us having to
  // fetch it via JS.
  reloadOnOrgChange(e) {
    const id = e.currentTarget.value
    const url = new URL(window.location.href)
    url.searchParams.set("organization_id", id)
    window.location.href = url.toString()
  }

  choice(radios) {
    const checked = radios.find(r => r.checked)
    return checked ? checked.value : null
  }

  toggle(el, show) {
    if (el) el.classList.toggle("hidden", !show)
  }
}
