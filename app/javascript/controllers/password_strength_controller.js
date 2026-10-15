import { Controller } from "@hotwired/stimulus"

// A new password's strength, drawn as five segments and one line that names
// what's still missing. The rules are User#password_complexity's: 8 or more
// characters, a capital, a lowercase letter, a number, a symbol. The submit
// target stays disabled until every rule passes.
//
// Lives on the <form> (see shared/auth/_password_field), so the input, the
// meter, the hint and the submit button are all in reach.
const RULES = [
  { test: (p) => p.length >= 8, noun: "8 or more characters", fix: "make it 8 characters or more" },
  { test: (p) => /[A-Z]/.test(p), noun: "a capital letter", fix: "add a capital letter" },
  { test: (p) => /[a-z]/.test(p), noun: "a lowercase letter", fix: "add a lowercase letter" },
  { test: (p) => /[0-9]/.test(p), noun: "a number", fix: "add a number" },
  { test: (p) => /[^A-Za-z0-9]/.test(p), noun: "a symbol", fix: "add a symbol, like ! or #" }
]

const EMPTY_HINT = "8 or more characters, with a capital, a number and a symbol."
const DONE_HINT = "That'll do nicely."

export default class extends Controller {
  static targets = ["input", "meter", "hint", "submit"]

  connect() {
    this.checkStrength()
  }

  checkStrength() {
    const password = this.hasInputTarget ? this.inputTarget.value : ""
    const results = RULES.map((rule) => rule.test(password))
    const met = results.filter(Boolean).length
    const missing = RULES.filter((_, i) => !results[i])

    this.paintMeter(met)
    this.writeHint(password, missing)

    if (this.hasSubmitTarget) {
      if (missing.length === 0) this.enableButton()
      else this.disableButton()
    }
  }

  paintMeter(met) {
    if (!this.hasMeterTarget) return
    Array.from(this.meterTarget.children).forEach((segment, i) => {
      segment.classList.toggle("bg-pink-500", i < met)
      segment.classList.toggle("bg-slate-200", i >= met)
    })
  }

  writeHint(password, missing) {
    if (!this.hasHintTarget) return
    const hint = this.hintTarget
    let text
    let quiet = false

    if (password.length === 0) {
      text = EMPTY_HINT
      quiet = true
    } else if (missing.length === 0) {
      text = DONE_HINT
    } else if (missing.length === 1) {
      const fix = missing[0].fix
      text = `Almost there. ${fix.charAt(0).toUpperCase()}${fix.slice(1)}.`
    } else {
      text = `Still needs ${this.list(missing.map((rule) => rule.noun))}.`
    }

    hint.textContent = text
    hint.classList.toggle("text-slate-500", quiet)
    hint.classList.toggle("text-slate-700", !quiet)
  }

  // "a, b and c"
  list(items) {
    if (items.length <= 1) return items.join("")
    return `${items.slice(0, -1).join(", ")} and ${items[items.length - 1]}`
  }

  enableButton() {
    this.submitTarget.removeAttribute("disabled")
    this.submitTarget.classList.remove("!opacity-50", "!cursor-not-allowed", "opacity-50", "cursor-not-allowed")
    this.submitTarget.classList.add("enabled")
  }

  disableButton() {
    this.submitTarget.setAttribute("disabled", "disabled")
    this.submitTarget.classList.remove("enabled")
    this.submitTarget.classList.add("!opacity-50", "!cursor-not-allowed")
  }
}
