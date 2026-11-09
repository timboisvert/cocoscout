import { Controller } from "@hotwired/stimulus"

// One person's Ticketing emails (Ticketing settings → Notifications, the
// edit modal): picking a plan shows what it sends on the switches, read-only;
// Pick my own makes them switchable, starting from what the plan before it
// sent. Counts follow along. Nothing saves until Save.
export default class extends Controller {
  static targets = ["switch", "groupCount", "planCount", "intro"]
  // notified: the kinds this person gets as notifications, not emails
  // (a manager's sales as they happen; none for a bare address).
  static values = { plans: Object, custom: Array, notified: Array }

  connect() {
    this.custom = new Set(this.customValue)
    this.render()
  }

  pick(event) {
    const plan = event.target.value
    if (plan === "custom" && this.previous && this.previous !== "custom") {
      this.custom = new Set(this.plansValue[this.previous] || [])
    }
    this.render()
  }

  changed(event) {
    if (event.target.checked) this.custom.add(event.target.dataset.kind)
    else this.custom.delete(event.target.dataset.kind)
    this.render()
  }

  get plan() {
    return this.element.querySelector("input[name='plan']:checked")?.value || "usual"
  }

  render() {
    const plan = this.plan
    const editable = plan === "custom"
    const on = editable ? this.custom : new Set(this.plansValue[plan] || [])

    this.switchTargets.forEach((input) => {
      input.checked = on.has(input.dataset.kind)
      input.disabled = !editable
      const label = input.closest("label")
      if (label) {
        label.classList.toggle("opacity-50", !editable)
        label.classList.toggle("cursor-not-allowed", !editable)
        label.classList.toggle("cursor-pointer", editable)
      }
    })

    this.groupCountTargets.forEach((el) => {
      const inGroup = this.switchTargets.filter((input) => input.dataset.group === el.dataset.group)
      el.textContent = `${inGroup.filter((input) => input.checked).length} of ${inGroup.length}`
    })

    this.planCountTargets.forEach((el) => {
      const kinds = el.dataset.plan === "custom" ? [...this.custom] : (this.plansValue[el.dataset.plan] || [])
      const notified = kinds.filter((kind) => this.notifiedValue.includes(kind)).length
      const count = kinds.length - notified
      const emails = count === 1 ? "1 email" : `${count} emails`
      el.textContent = notified ? `${emails} · ${notified === 1 ? "1 notification" : `${notified} notifications`}` : emails
    })

    if (this.hasIntroTarget) {
      this.introTarget.textContent = editable ? "Switch on the emails they get." : "What this plan sends. Choose Pick my own to change one."
    }
    this.previous = plan
  }
}
