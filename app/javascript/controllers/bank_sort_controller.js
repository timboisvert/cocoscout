import { Controller } from "@hotwired/stimulus"

// Books → Bank → Sort (Tim, 2026-11-03). Part 1 (a payee): the answer
// chosen shows or hides the category and payee fields and words the
// button. Part 2 (a line): a chip sets the category sheet to that
// answer (or Ignore, which swaps the record fields for the note);
// "Something else…" opens the sheet. The hidden answer field says which.
//
// Targets: answer (hidden input), chip, picker (the category picker's
// wrapper), recordFields, ignoreFields, submit (its button params carry
// the wording for each answer; "{lines}" in it is the count the rule
// will run over: the payee's open lines plus the look-alikes ticked).
export default class extends Controller {
    static targets = ["answer", "chip", "picker", "recordFields", "ignoreFields", "ruleFields", "submit", "moreLine", "showAll", "linesTitle"]

    // Part 1: every line the payee has, in place of the three shown, and back.
    showAll() {
        const open = this.moreLineTargets[0]?.classList.contains("hidden")
        this.moreLineTargets.forEach(li => li.classList.toggle("hidden", !open))
        this.showAllTarget.textContent = open ? this.showAllTarget.dataset.few : this.showAllTarget.dataset.all
        if (this.hasLinesTitleTarget) this.linesTitleTarget.textContent = open ? this.linesTitleTarget.dataset.all : this.linesTitleTarget.dataset.few
    }

    // Part 1: the radio chosen. "It varies" makes no rule, so nothing about one shows.
    choose(event) {
        const value = event.target.value
        if (this.hasRecordFieldsTarget) this.recordFieldsTarget.classList.toggle("hidden", value !== "record")
        if (this.hasRuleFieldsTarget) this.ruleFieldsTarget.classList.toggle("hidden", value === "varies")
        this.word(value)
    }

    // Part 1: a look-alike ticked or unticked.
    also() {
        this.word(this.element.querySelector("input[type=radio][name=answer]:checked")?.value || "record")
    }

    // Part 2: a chip.
    pick(event) {
        const chip = event.currentTarget
        const answer = chip.dataset.answer || "record"
        this.chipTargets.forEach(c => { if (c === chip) c.setAttribute("data-on", ""); else c.removeAttribute("data-on") })
        if (this.hasAnswerTarget) this.answerTarget.value = answer
        if (answer === "record") this.categoryPicker()?.set(chip.dataset.key)
        this.swap(answer)
        this.word(answer)
    }

    // Part 2: the whole sheet.
    other() {
        this.chipTargets.forEach(c => c.removeAttribute("data-on"))
        if (this.hasAnswerTarget) this.answerTarget.value = "record"
        this.swap("record")
        this.word("record")
        this.categoryPicker()?.open()
    }

    // The sheet's own choice (a change on its hidden input) unmarks the chips that don't match.
    pickerChanged(event) {
        const key = event.target.value
        this.chipTargets.forEach(c => { if (c.dataset.key === key && key) c.setAttribute("data-on", ""); else c.removeAttribute("data-on") })
    }

    swap(answer) {
        if (this.hasRecordFieldsTarget) this.recordFieldsTarget.classList.toggle("hidden", answer === "ignore")
        if (this.hasIgnoreFieldsTarget) this.ignoreFieldsTarget.classList.toggle("hidden", answer !== "ignore")
        if (answer === "ignore") this.ignoreFieldsTarget?.querySelector("input")?.focus()
    }

    word(answer) {
        if (!this.hasSubmitTarget) return
        const text = this.submitTarget.dataset[`bankSort${answer.charAt(0).toUpperCase() + answer.slice(1)}TextParam`]
        const span = this.submitTarget.querySelector("span")
        if (text && span) span.textContent = text.replace("{lines}", this.lines())
        else if (span && answer === "skip") span.textContent = "Go on"
    }

    // "127 lines": the payee's own plus every look-alike ticked.
    lines() {
        let n = parseInt(this.submitTarget.dataset.bankSortBaseParam || "0", 10)
        this.element.querySelectorAll("input[name='also[]']:checked").forEach(box => { n += parseInt(box.dataset.count || "0", 10) })
        return `${n} ${n === 1 ? "line" : "lines"}`
    }

    categoryPicker() {
        if (!this.hasPickerTarget) return null
        return this.application.getControllerForElementAndIdentifier(this.pickerTarget, "category-picker")
    }
}
