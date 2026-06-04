import { Controller } from "@hotwired/stimulus"

// Live character counter for textareas/inputs. Shows remaining chars
// and tints amber as it nears the limit, red once over.
//
// Markup:
//   <div data-controller="char-counter" data-char-counter-max-value="175">
//     <textarea data-char-counter-target="input" maxlength="175"></textarea>
//     <span data-char-counter-target="readout"></span>
//   </div>
export default class extends Controller {
  static targets = ["input", "readout"]
  static values  = { max: Number }

  connect() {
    this.inputTarget.addEventListener("input", () => this.update())
    this.update()
  }

  update() {
    const len = this.inputTarget.value.length
    const remaining = this.maxValue - len
    this.readoutTarget.textContent = `${remaining} left`
    this.readoutTarget.classList.remove("text-gray-400", "text-amber-600", "text-red-600")
    if (remaining < 0)        this.readoutTarget.classList.add("text-red-600")
    else if (remaining < 25)  this.readoutTarget.classList.add("text-amber-600")
    else                      this.readoutTarget.classList.add("text-gray-400")
  }
}
