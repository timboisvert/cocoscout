import { Controller } from "@hotwired/stimulus"

// The door on show night (DoorController). Scans QR tickets with the camera,
// finds people by name, checks in whole orders, and keeps the counts fresh by
// polling (there's no ActionCable). Every result shows as a big colored
// banner with a sound and a buzz, so the person at the door never has to read
// small print. The QR library loads only when scanning starts.
export default class extends Controller {
    static targets = ["video", "viewport", "startButton", "stopButton", "banner", "searchInput", "results", "checkedIn", "sold"]
    static values = { checkInUrl: String, statsUrl: String, searchUrl: String, undoUrl: String }

    static BANNER_CLASSES = {
        admitted: "bg-green-600 text-white",
        already: "bg-amber-300 text-gray-900",
        error: "bg-red-600 text-white"
    }

    connect() {
        this.recentCodes = new Map()
        this.pollTimer = setInterval(() => this.refreshStats(), 5000)
    }

    disconnect() {
        clearInterval(this.pollTimer)
        clearTimeout(this.searchTimer)
        clearTimeout(this.bannerTimer)
        this.stopScanning()
    }

    async startScanning() {
        try {
            const { default: QrScanner } = await import("qr-scanner")
            this.viewportTarget.classList.remove("hidden")
            this.scanner ||= new QrScanner(this.videoTarget, (result) => this.scanned(result.data), {
                returnDetailedScanResult: true,
                highlightScanRegion: true,
                preferredCamera: "environment"
            })
            await this.scanner.start()
            this.startButtonTarget.classList.add("hidden")
            this.stopButtonTarget.classList.remove("hidden")
        } catch (error) {
            this.viewportTarget.classList.add("hidden")
            this.showBanner("error", "The camera didn't start. Allow camera access for this page, or search by name instead.")
        }
    }

    stopScanning() {
        if (this.scanner) this.scanner.stop()
        if (this.hasViewportTarget) this.viewportTarget.classList.add("hidden")
        if (this.hasStopButtonTarget) this.stopButtonTarget.classList.add("hidden")
        if (this.hasStartButtonTarget) this.startButtonTarget.classList.remove("hidden")
    }

    // The camera reports the same code many times a second; act once, and
    // not again for that code for a few seconds.
    scanned(code) {
        const now = Date.now()
        if (this.busy || (this.recentCodes.get(code) || 0) > now - 4000) return
        this.recentCodes.set(code, now)
        this.checkIn(code)
    }

    async checkIn(code) {
        this.busy = true
        try {
            const data = await this.post(this.checkInUrlValue, { code })
            this.showResult(data)
        } catch {
            this.showBanner("error", "Couldn't reach CocoScout. Check the connection and scan again.")
        } finally {
            this.busy = false
        }
    }

    async checkInOrder(event) {
        const button = event.currentTarget
        button.disabled = true
        try {
            const data = await this.post(button.dataset.url, {})
            this.showResult(data)
            this.runSearch()
        } catch {
            button.disabled = false
            this.showBanner("error", "Couldn't reach CocoScout. Try again.")
        }
    }

    async undo(event) {
        const ticketId = event.currentTarget.dataset.ticketId
        try {
            const data = await this.post(this.undoUrlValue, { ticket_id: ticketId })
            this.showBanner(data.ok ? "already" : "error", data.message)
            if (data.counts) this.updateCounts(data.counts)
        } catch {
            this.showBanner("error", "Couldn't reach CocoScout. Try again.")
        }
    }

    showResult(data) {
        const tone = data.kind === "admitted" ? "admitted" : data.kind === "already" ? "already" : "error"
        const lines = [data.message]
        if (data.holder) lines.unshift(data.holder)
        this.showBanner(tone, lines, data.kind === "admitted" ? data.ticket_id : null)
        if (data.counts) this.updateCounts(data.counts)
    }

    showBanner(tone, lines, undoTicketId = null) {
        const banner = this.bannerTarget
        banner.className = `mt-4 rounded-xl px-4 py-4 text-center ${this.constructor.BANNER_CLASSES[tone]}`
        banner.replaceChildren()
        ;[].concat(lines).forEach((line, index) => {
            const el = document.createElement("div")
            el.className = index === 0 ? "text-xl font-bold" : "text-sm font-medium mt-1"
            el.textContent = line
            banner.appendChild(el)
        })
        if (undoTicketId) {
            const undo = document.createElement("button")
            undo.type = "button"
            undo.className = "mt-2 text-sm font-medium underline underline-offset-2"
            undo.textContent = "Undo"
            undo.dataset.ticketId = undoTicketId
            undo.dataset.action = "click->door#undo"
            banner.appendChild(undo)
        }
        this.feedback(tone)
        clearTimeout(this.bannerTimer)
        this.bannerTimer = setTimeout(() => banner.classList.add("hidden"), 8000)
    }

    // A rising chirp for admitted, a low buzz for anything else, and a
    // vibration where the phone allows it.
    feedback(tone) {
        try {
            this.audio ||= new (window.AudioContext || window.webkitAudioContext)()
            const osc = this.audio.createOscillator()
            const gain = this.audio.createGain()
            osc.connect(gain)
            gain.connect(this.audio.destination)
            osc.type = tone === "admitted" ? "sine" : "square"
            osc.frequency.value = tone === "admitted" ? 880 : 220
            gain.gain.value = 0.15
            osc.start()
            osc.stop(this.audio.currentTime + (tone === "admitted" ? 0.15 : 0.4))
        } catch { /* no sound is fine */ }
        if (navigator.vibrate) navigator.vibrate(tone === "admitted" ? 60 : [120, 80, 120])
    }

    search() {
        clearTimeout(this.searchTimer)
        this.searchTimer = setTimeout(() => this.runSearch(), 250)
    }

    async runSearch() {
        const q = this.searchInputTarget.value.trim()
        const url = `${this.searchUrlValue}?q=${encodeURIComponent(q)}`
        try {
            const response = await fetch(url, { headers: { Accept: "text/html" }, credentials: "same-origin" })
            if (response.ok && q === this.searchInputTarget.value.trim()) {
                this.resultsTarget.innerHTML = await response.text()
            }
        } catch { /* the next keystroke tries again */ }
    }

    async refreshStats() {
        if (document.hidden) return
        try {
            const response = await fetch(this.statsUrlValue, { headers: { Accept: "application/json" }, credentials: "same-origin" })
            if (response.ok) this.updateCounts(await response.json())
        } catch { /* keep the last numbers */ }
    }

    updateCounts(counts) {
        this.checkedInTarget.textContent = counts.checked_in
        this.soldTarget.textContent = counts.sold
    }

    async post(url, body) {
        const token = document.querySelector('meta[name="csrf-token"]')?.content
        const response = await fetch(url, {
            method: "POST",
            headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": token },
            credentials: "same-origin",
            body: JSON.stringify(body)
        })
        if (!response.ok && response.status !== 403) throw new Error(`HTTP ${response.status}`)
        return response.json()
    }
}
