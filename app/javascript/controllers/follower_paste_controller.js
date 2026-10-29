import { Controller } from "@hotwired/stimulus"

const CHECK_FAILED = "Couldn't check that paste just now. You can still add them: we'll skip anyone already on the list, unsubscribed or bounced."

// The Add people window on a mailing list: one person, or many pasted, on
// the usual tabs (tabs_controller); this swaps the footer's buttons to match
// (tabs:change).
// Add is ready once there's a paste and the permission box is ticked; the
// server sorts out who's new when it's pressed. Check is an optional preview:
// it asks the server what the paste would add (new, already on it,
// unsubscribed, bounced) and shows it, or says why it couldn't.
export default class extends Controller {
    static targets = ["text", "result", "permission", "addPaste", "addOne"]
    static values = { checkUrl: String }

    connect() {
        this.addable = null
        this.showFooter(true)
        this.refresh()
    }

    tabChanged(event) {
        const one = event.detail.index === 0
        this.showFooter(one)
        if (!one) this.textTarget.focus()
    }

    // style, not a class: Tailwind's hidden loses to the buttons' inline-flex
    showFooter(one) {
        if (this.hasAddOneTarget) this.addOneTarget.style.display = one ? "" : "none"
        if (this.hasAddPasteTarget) this.addPasteTarget.style.display = one ? "none" : ""
    }

    async check(event) {
        event?.preventDefault()
        const text = this.textTarget.value.trim()
        if (!text) return this.say("Paste some names and emails first, one per line.")
        const token = document.querySelector('meta[name="csrf-token"]')?.content
        const body = new FormData()
        body.append("text", text)
        let html
        try {
            const response = await fetch(this.checkUrlValue, { method: "POST", body, headers: { "X-CSRF-Token": token, "Accept": "text/html" } })
            // a redirect (signed out, not on Pro) lands on a whole page, not the preview
            if (!response.ok || response.redirected) throw new Error(`check ${response.status}`)
            html = await response.text()
        } catch (error) {
            return this.say(CHECK_FAILED)
        }
        const holder = document.createElement("div")
        holder.innerHTML = html
        const box = holder.querySelector("[data-follower-paste-addable]")
        if (!box) return this.say(CHECK_FAILED)
        if (this.textTarget.value.trim() !== text) return // edited while checking
        this.resultTarget.replaceChildren(...holder.childNodes)
        this.addable = parseInt(box.dataset.followerPasteAddable, 10) || 0
        this.refresh()
    }

    say(words) {
        const note = document.createElement("p")
        note.className = "rounded-lg border border-amber-200 bg-amber-50 px-3.5 py-2.5 text-sm text-amber-800"
        note.textContent = words
        this.resultTarget.replaceChildren(note)
        this.addable = null
        this.refresh()
    }

    edited() {
        this.addable = null
        this.resultTarget.replaceChildren()
        this.refresh()
    }

    refresh() {
        if (!this.hasAddPasteTarget) return
        const button = this.addPasteTarget.querySelector("button") || this.addPasteTarget
        button.disabled = !(this.textTarget.value.trim() && this.permissionTarget.checked)
        // the words live in the button's span; setting the button's own text would wipe it
        const label = button.querySelector("span") || button
        label.textContent = this.addable > 0 ? `Add ${this.addable} ${this.addable === 1 ? "person" : "people"}` : "Add people"
    }
}
