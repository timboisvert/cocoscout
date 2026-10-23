import { Controller } from "@hotwired/stimulus"

// The Add people window on a mailing list: one person, or many pasted.
// Check asks the server what a paste would add (new, already on it,
// unsubscribed, bounced) and shows it before anything's added; Add is ready
// once there's someone new and the permission box is ticked.
export default class extends Controller {
    static targets = ["onePane", "pastePane", "oneTab", "pasteTab", "text", "result", "permission", "addPaste", "addOne"]
    static values = { checkUrl: String }

    connect() {
        this.addable = 0
        this.showOne()
    }

    showOne() { this.toggle(true) }
    showPaste() { this.toggle(false) }

    toggle(one) {
        // style, not a class: these are flex boxes, and Tailwind's hidden loses to flex
        this.onePaneTarget.style.display = one ? "" : "none"
        this.pastePaneTarget.style.display = one ? "none" : ""
        if (this.hasAddOneTarget) this.addOneTarget.style.display = one ? "" : "none"
        if (this.hasAddPasteTarget) this.addPasteTarget.style.display = one ? "none" : ""
        this.setTab(this.oneTabTarget, one)
        this.setTab(this.pasteTabTarget, !one)
    }

    setTab(tab, on) {
        tab.classList.toggle("bg-pink-500", on)
        tab.classList.toggle("text-white", on)
        tab.classList.toggle("bg-gray-100", !on)
        tab.classList.toggle("text-gray-700", !on)
    }

    async check(event) {
        event?.preventDefault()
        const text = this.textTarget.value.trim()
        if (!text) return
        const token = document.querySelector('meta[name="csrf-token"]')?.content
        const body = new FormData()
        body.append("text", text)
        const response = await fetch(this.checkUrlValue, { method: "POST", body, headers: { "X-CSRF-Token": token, "Accept": "text/html" } })
        if (!response.ok) return
        this.resultTarget.innerHTML = await response.text()
        const box = this.resultTarget.querySelector("[data-follower-paste-addable]")
        this.addable = box ? parseInt(box.dataset.followerPasteAddable, 10) || 0 : 0
        this.refresh()
    }

    edited() {
        this.addable = 0
        this.resultTarget.innerHTML = ""
        this.refresh()
    }

    refresh() {
        if (!this.hasAddPasteTarget) return
        const button = this.addPasteTarget.querySelector("button") || this.addPasteTarget
        const ready = this.addable > 0 && this.permissionTarget.checked
        button.disabled = !ready
        const label = button.querySelector("[data-label]") || button
        label.textContent = this.addable > 0 ? `Add ${this.addable} ${this.addable === 1 ? "person" : "people"}` : "Add people"
    }
}
