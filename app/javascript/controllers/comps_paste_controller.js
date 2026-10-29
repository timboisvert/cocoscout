import { Controller } from "@hotwired/stimulus"

const PREVIEW_FAILED = "Couldn't preview that list just now. Press Preview to try again."

// The Comps modal's two ways in, on the usual tabs (tabs_controller): One at
// a time (the default), or a pasted list. This swaps the footer's buttons to
// match (tabs:change).
// The pasted list's footer button always does something: Preview asks the
// server what the list would give (who, how many, against the comps, seats
// and allowance left, and the lines to fix) and shows it, or says why it
// couldn't; once that preview is ready the button is Give N comps. Any edit
// to the list, the ticket type or the email switch goes back to Preview.
export default class extends Controller {
    static targets = ["pastePane", "text", "result", "giveOne", "preview", "give"]
    static values = { url: String }

    connect() {
        this.ready = 0
        this.checking = false
        this.pasting = false
        this.refresh()
    }

    tabChanged(event) {
        this.pasting = event.detail.index === 1
        this.refresh()
        if (this.pasting) this.textTarget.focus()
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

    // style, not a class: Tailwind's hidden loses to the buttons' inline-flex
    refresh() {
        this.giveOneTarget.style.display = this.pasting ? "none" : ""
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
