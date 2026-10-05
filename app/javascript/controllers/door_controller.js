import { Controller } from "@hotwired/stimulus"

// The door on show night (DoorController). Two ways in: the list (everyone
// with a ticket, filtered as you type, one box per party that checks the
// whole party in) and the camera, which scans QR tickets. Keeps the counts
// fresh by polling (there's no ActionCable). Every result shows as a big
// colored banner with a sound and a buzz, so the person at the door never
// has to read small print. The QR library loads only when scanning starts.
export default class extends Controller {
    static targets = ["video", "viewport", "startButton", "stopButton", "banner", "checkedIn", "sold", "deliveries",
                      "modeButton", "listPanel", "scanPanel", "filterInput", "filterChip", "deliverChip", "results", "party", "nobody",
                      "sellButton", "sellPanel"]
    static values = { checkInUrl: String, statsUrl: String, listUrl: String, undoUrl: String, deliveriesUrl: String, listingId: Number }

    static BANNER_CLASSES = {
        admitted: "bg-green-600 text-white",
        already: "bg-amber-300 text-gray-900",
        error: "bg-red-600 text-white"
    }
    static ACTIVE = ["ring-2", "ring-pink-500", "!bg-pink-50", "!text-pink-700"]

    connect() {
        this.recentCodes = new Map()
        this.filterState = "all"
        this.applyMode(this.rememberedMode())
        this.applyFilter()
        this.pollTimer = setInterval(() => this.refreshStats(), 5000)
        this.listTimer = setInterval(() => this.refreshList(), 30000)
    }

    disconnect() {
        clearInterval(this.pollTimer)
        clearInterval(this.listTimer)
        clearTimeout(this.filterTimer)
        clearTimeout(this.bannerTimer)
        this.stopScanning()
    }

    // List or Scan. The choice sticks on this phone. Scan starts the camera
    // at once; leaving Scan stops it.
    setMode(event) {
        this.applyMode(event.currentTarget.dataset.mode)
    }

    applyMode(mode) {
        this.mode = mode === "scan" ? "scan" : "list"
        this.modeButtonTargets.forEach((button) => {
            const on = button.dataset.mode === this.mode
            button.setAttribute("aria-pressed", on)
            this.constructor.ACTIVE.forEach((c) => button.classList.toggle(c, on))
        })
        this.listPanelTarget.classList.toggle("hidden", this.mode !== "list")
        this.scanPanelTarget.classList.toggle("hidden", this.mode !== "scan")
        try { window.localStorage.setItem(this.modeKey(), this.mode) } catch (_e) { /* fine without */ }
        if (this.mode === "scan") this.startScanning()
        else this.stopScanning()
    }

    rememberedMode() {
        try { return window.localStorage.getItem(this.modeKey()) || "list" } catch (_e) { return "list" }
    }

    modeKey() {
        return `cocoscout:door-mode:${this.listingIdValue}`
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
            this.showBanner("error", "The camera didn't start. Allow camera access for this page, or use the list instead.")
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
            this.refreshList()
        } catch {
            this.showBanner("error", "Couldn't reach CocoScout. Check the connection and scan again.")
        } finally {
            this.busy = false
        }
    }

    // The box next to a party: everyone on the order, in.
    async checkInOrder(event) {
        const button = event.currentTarget
        button.disabled = true
        try {
            const data = await this.post(button.dataset.url, {})
            this.showResult(data)
            this.refreshList()
        } catch {
            button.disabled = false
            this.showBanner("error", "Couldn't reach CocoScout. Try again.")
        }
    }

    // A pre-bought bottle delivered to the table.
    async fulfill(event) {
        const button = event.currentTarget
        button.disabled = true
        try {
            const data = await this.post(button.dataset.url, {})
            this.showBanner("admitted", data.message)
            this.refreshList()
            this.refreshDeliveries()
        } catch {
            button.disabled = false
            this.showBanner("error", "Couldn't reach CocoScout. Try again.")
        }
    }

    // The "To deliver" line, fresh from the server.
    async refreshDeliveries() {
        if (!this.hasDeliveriesTarget || !this.deliveriesUrlValue) return
        try {
            const response = await fetch(this.deliveriesUrlValue, { headers: { Accept: "text/html" }, credentials: "same-origin" })
            if (!response.ok) return
            const html = await response.text()
            this.deliveriesTarget.innerHTML = html
            this.deliveriesTarget.classList.toggle("hidden", html.trim() === "")
            if (this.hasDeliverChipTarget) this.deliverChipTarget.classList.toggle("hidden", html.trim() === "")
        } catch { /* the next refresh tries again */ }
    }

    async undo(event) {
        const ticketId = event.currentTarget.dataset.ticketId
        try {
            const data = await this.post(this.undoUrlValue, { ticket_id: ticketId })
            this.showBanner(data.ok ? "already" : "error", data.message)
            if (data.counts) this.updateCounts(data.counts)
            this.refreshList()
        } catch {
            this.showBanner("error", "Couldn't reach CocoScout. Try again.")
        }
    }

    showResult(data) {
        const tone = data.kind === "admitted" ? "admitted" : data.kind === "already" ? "already" : "error"
        const lines = [data.message]
        if (data.holder) lines.unshift(data.holder)
        if (data.party) lines.push(data.party)
        this.showBanner(tone, lines, data.kind === "admitted" ? data.ticket_id : null, data.items || [])
        if (data.counts) this.updateCounts(data.counts)
    }

    // items: what they pre-bought (a bottle), each with a Delivered tap. A
    // banner with something still to deliver stays until the next scan.
    showBanner(tone, lines, undoTicketId = null, items = []) {
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
        items.forEach((item) => {
            const row = document.createElement("div")
            row.className = "mt-3 flex items-center justify-between gap-3 rounded-lg bg-white/90 px-3 py-2 text-left text-gray-900"
            const label = document.createElement("div")
            label.className = "text-base font-semibold"
            label.textContent = item.fulfilled ? `${item.label} · delivered` : item.label
            row.appendChild(label)
            if (!item.fulfilled) {
                const button = document.createElement("button")
                button.type = "button"
                button.className = "rounded-lg bg-pink-500 px-3 py-1.5 text-sm font-semibold text-white"
                button.textContent = "Delivered"
                button.dataset.url = item.fulfill_url
                button.dataset.action = "click->door#fulfillFromBanner"
                row.appendChild(button)
            }
            banner.appendChild(row)
        })
        this.feedback(tone)
        clearTimeout(this.bannerTimer)
        const waiting = items.some((item) => !item.fulfilled)
        if (!waiting) this.bannerTimer = setTimeout(() => banner.classList.add("hidden"), 8000)
    }

    // Deliver a pre-bought product straight from the banner.
    async fulfillFromBanner(event) {
        const button = event.currentTarget
        button.disabled = true
        try {
            const data = await this.post(button.dataset.url, {})
            const row = button.parentElement
            row.firstChild.textContent = `${row.firstChild.textContent} · delivered`
            button.remove()
            if (!this.bannerTarget.querySelector("[data-action='click->door#fulfillFromBanner']")) {
                this.bannerTimer = setTimeout(() => this.bannerTarget.classList.add("hidden"), 8000)
            }
            if (data.counts) this.updateCounts(data.counts)
            this.refreshList()
            this.refreshDeliveries()
        } catch {
            button.disabled = false
        }
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

    // The list filters as you type, on the rows already on the page.
    filter() {
        clearTimeout(this.filterTimer)
        this.filterTimer = setTimeout(() => this.applyFilter(), 120)
    }

    chip(event) {
        this.filterState = event.currentTarget.dataset.filter
        this.applyFilter()
    }

    applyFilter() {
        const words = this.hasFilterInputTarget ? this.filterInputTarget.value.trim().toLowerCase() : ""
        this.filterChipTargets.forEach((chip) => {
            const on = chip.dataset.filter === this.filterState
            chip.setAttribute("aria-pressed", on)
            this.constructor.ACTIVE.forEach((c) => chip.classList.toggle(c, on))
        })
        let shown = 0
        this.partyTargets.forEach((row) => {
            const state = row.dataset.state
            const byState = this.filterState === "all" ||
                (this.filterState === "out" && state !== "in") ||
                (this.filterState === "in" && state !== "out") ||
                (this.filterState === "deliver" && row.dataset.deliver === "1")
            const byWords = words === "" || row.dataset.search.includes(words)
            const show = byState && byWords
            row.classList.toggle("hidden", !show)
            if (show) shown += 1
        })
        if (this.hasNobodyTarget) this.nobodyTarget.classList.toggle("hidden", shown > 0 || this.partyTargets.length === 0)
    }

    // The whole list again, from the server, with the filter kept.
    async refreshList() {
        if (!this.listUrlValue || document.hidden) return
        try {
            const response = await fetch(this.listUrlValue, { headers: { Accept: "text/html" }, credentials: "same-origin" })
            if (!response.ok) return
            this.resultsTarget.innerHTML = await response.text()
            this.applyFilter()
        } catch { /* the next refresh tries again */ }
    }

    async refreshStats() {
        if (document.hidden) return
        try {
            const response = await fetch(this.statsUrlValue, { headers: { Accept: "application/json" }, credentials: "same-origin" })
            if (response.ok) this.updateCounts(await response.json())
        } catch { /* keep the last numbers */ }
        this.refreshDeliveries()
    }

    updateCounts(counts) {
        this.checkedInTarget.textContent = counts.checked_in
        this.soldTarget.textContent = counts.sold
    }

    toggleSell() {
        const open = this.sellPanelTarget.classList.toggle("hidden")
        this.sellButtonTarget.classList.toggle("hidden", !open)
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
