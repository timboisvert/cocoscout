import { Controller } from "@hotwired/stimulus"

// A money category picked from a sheet of our own (shared/category_picker):
// the button shows the choice and its line, the sheet lists every category
// with what goes in it, alphabetical, with a box to find one when the list
// is long. The hidden input carries the key and gets a change event when it
// changes, so a form around it can react. Another controller sets it with
// set(key) and turns it off with disable(true).
export default class extends Controller {
    static targets = ["input", "button", "label", "hint", "modal", "search", "list", "option", "check", "empty"]

    connect() {
        this.keyHandler = this.handleKeydown.bind(this)
    }

    disconnect() {
        window.removeEventListener("keydown", this.keyHandler, true)
    }

    open() {
        if (this.buttonTarget.disabled) return
        if (this.hasSearchTarget) { this.searchTarget.value = ""; this.filter() }
        this.mark(this.inputTarget.value)
        this.modalTarget.classList.remove("hidden")
        window.addEventListener("keydown", this.keyHandler, true)
        const chosen = this.optionTargets.find(o => o.dataset.key === this.inputTarget.value)
        if (this.hasSearchTarget) this.searchTarget.focus()
        else (chosen || this.optionTargets[0])?.focus()
        if (chosen) chosen.scrollIntoView({ block: "center" })
    }

    close() {
        if (this.modalTarget.classList.contains("hidden")) return
        this.modalTarget.classList.add("hidden")
        window.removeEventListener("keydown", this.keyHandler, true)
        this.buttonTarget.focus()
    }

    closeOnBackdrop(event) {
        if (event.target === event.currentTarget) this.close()
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    // Escape closes this sheet and nothing behind it.
    handleKeydown(event) {
        if (event.key !== "Escape") return
        event.stopPropagation()
        event.preventDefault()
        this.close()
    }

    choose(event) {
        this.set(event.currentTarget.dataset.key)
        this.close()
    }

    // The choice by key ("" for none): the input, the button and the ticks.
    set(key) {
        const option = this.optionTargets.find(o => o.dataset.key === key)
        const value = option ? key : ""
        const changed = this.inputTarget.value !== value
        this.inputTarget.value = value
        this.labelTarget.textContent = option ? option.dataset.label : this.inputTarget.dataset.prompt || "Choose one"
        this.labelTarget.classList.toggle("text-gray-900", !!option)
        this.labelTarget.classList.toggle("text-gray-500", !option)
        const description = option ? option.dataset.description : ""
        this.hintTarget.textContent = description
        this.hintTarget.classList.toggle("hidden", !description)
        this.mark(value)
        if (changed) this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
    }

    get value() {
        return this.inputTarget.value
    }

    has(key) {
        return this.optionTargets.some(o => o.dataset.key === key)
    }

    disable(off) {
        this.inputTarget.disabled = off
        this.buttonTarget.disabled = off
    }

    focus() {
        this.buttonTarget.focus()
    }

    mark(key) {
        this.optionTargets.forEach(o => o.setAttribute("aria-selected", o.dataset.key === key ? "true" : "false"))
        this.checkTargets.forEach(c => c.classList.toggle("invisible", c.closest("[data-key]").dataset.key !== key))
    }

    filter() {
        const words = (this.hasSearchTarget ? this.searchTarget.value : "").trim().toLowerCase()
        let shown = 0
        this.optionTargets.forEach(o => {
            const fits = !words || `${o.dataset.label} ${o.dataset.description}`.toLowerCase().includes(words)
            o.parentElement.classList.toggle("hidden", !fits)
            if (fits) shown += 1
        })
        if (this.hasEmptyTarget) this.emptyTarget.classList.toggle("hidden", shown > 0)
    }
}
