import { Controller } from "@hotwired/stimulus"

const PREVIEW_FAILED = "Couldn't preview that list just now. Press Preview to try again."

// The Comps modal's two tabs: one person (the default), or a pasted list.
// The pasted list's footer button always does something: Preview asks the
// server what the list would give (who, how many, against the comps, seats
// and allowance left, and the lines to fix) and shows it, or says why it
// couldn't; once that preview is ready the button is Give N comps. Any edit
// to the list, the ticket type or the email switch goes back to Preview.
export default class extends Controller {
    static targets = ["onePane", "pastePane", "oneTab", "pasteTab", "text", "result", "giveOne", "preview", "give"]
    static values = { url: String }

    connect() {
        this.ready = 0
        this.checking = false
        this.showOne()
    }

    showOne() { this.toggle(true) }
    showPaste() { this.toggle(false) }

    toggle(one) {
        this.pasting = !one
        // style, not a class: Tailwind's hidden loses to the button's inline-flex
        this.onePaneTarget.style.display = one ? "" : "none"
        this.pastePaneTarget.style.display = one ? "none" : ""
        this.giveOneTarget.style.display = one ? "" : "none"
        this.setTab(this.oneTabTarget, one)
        this.setTab(this.pasteTabTarget, !one)
        this.refresh()
        if (!one) this.textTarget.focus()
    }

    setTab(tab, on) {
        tab.classList.toggle("bg-pink-500", on)
        tab.classList.toggle("text-white", on)
        tab.classList.toggle("bg-gray-100", !on)
        tab.classList.toggle("text-gray-700", !on)
    }

    // Enter in a field submits the form: preview first unless it's ready.
    submit(event) {
        if (this.ready > 0) return
        event.preventDefault()
        this.preview()
    }

    async preview(event) {
        event?.preventDefault()
        if (this.checking) return
        const text = this.textTarget.value.trim()
        if (!text) return this.say("Paste some names and emails first, one per line.")

        const body = new FormData(this.pastePaneTarget)
        const token = document.querySelector('meta[name="csrf-token"]')?.content
        this.checking = true
        this.setLabel(this.previewTarget, "Checking…")
        let html
        try {
            const response = await fetch(this.urlValue, { method: "POST", body, headers: { "X-CSRF-Token": token, "Accept": "text/html" } })
            // a redirect (signed out, not on Pro) lands on a whole page, not the preview
            if (!response.ok || response.redirected) throw new Error(`preview ${response.status}`)
            html = await response.text()
        } catch (error) {
            return this.say(PREVIEW_FAILED)
        } finally {
            this.checking = false
            this.setLabel(this.previewTarget, "Preview")
        }
        const holder = document.createElement("div")
        holder.innerHTML = html
        const box = holder.querySelector("[data-comps-paste-ready]")
        if (!box) return this.say(PREVIEW_FAILED)
        if (this.textTarget.value.trim() !== text) return // edited while checking
        this.resultTarget.replaceChildren(...holder.childNodes)
        this.ready = parseInt(box.dataset.compsPasteReady, 10) || 0
        this.refresh()
    }

    say(words) {
        const note = document.createElement("p")
        note.className = "rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900"
        note.textContent = words
        this.resultTarget.replaceChildren(note)
        this.ready = 0
        this.refresh()
    }

    edited() {
        if (this.ready === 0 && !this.resultTarget.hasChildNodes()) return
        this.ready = 0
        this.resultTarget.replaceChildren()
        this.refresh()
    }

    refresh() {
        const giving = this.pasting && this.ready > 0
        this.previewTarget.style.display = this.pasting && !giving ? "" : "none"
        this.giveTarget.style.display = giving ? "" : "none"
        if (giving) this.setLabel(this.giveTarget, `Give ${this.ready} ${this.ready === 1 ? "comp" : "comps"}`)
    }

    // the words live in the button's span; setting the button's own text would wipe it
    setLabel(button, words) {
        (button.querySelector("span") || button).textContent = words
    }
}
