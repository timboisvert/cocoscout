import { Controller } from "@hotwired/stimulus"

// The Tickets question's "Somewhere else" answer: as a link is pasted, name
// the site it's on ("Ticket Tailor: got it"), the way the server will when
// it makes that site a ticket source. The sites come from TicketLink::KNOWN_SITES.
export default class extends Controller {
    static targets = ["url", "siteNote"]
    static values = { sites: Object }

    connect() {
        this.recognize()
    }

    recognize() {
        if (!this.hasUrlTarget || !this.hasSiteNoteTarget) return
        const raw = this.urlTarget.value.trim()
        if (!raw) return this.say("")
        let host
        try {
            host = new URL(/^https?:\/\//i.test(raw) ? raw : `https://${raw}`).hostname.toLowerCase().replace(/^www\./, "")
        } catch {
            return this.say("")
        }
        if (!host.includes(".")) return this.say("")
        const key = Object.keys(this.sitesValue).find(site => host === site || host.endsWith(`.${site}`))
        if (key) return this.say(`${this.sitesValue[key]}: got it. It joins your ticket sources, so the financials know it too.`)
        const guess = host.split(".").slice(-2, -1)[0] || host
        this.say(`We'll list it as ${guess.charAt(0).toUpperCase()}${guess.slice(1)}.`)
    }

    say(text) {
        this.siteNoteTarget.textContent = text
        this.siteNoteTarget.classList.toggle("hidden", text === "")
    }
}
