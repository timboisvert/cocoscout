import { Controller } from "@hotwired/stimulus"

// A contract's services (manage/contracts/_services_fields): the services on
// top, where each usually goes ("Usually on: every show"), and "Each date"
// below with each date's chips and cost. Every date's inputs live in that
// date's Edit; this keeps the chips, costs and totals in step, opens and
// cancels the Edits, and edits several ticked dates at once.
export default class extends Controller {
    static targets = ["service", "include", "body", "price", "usual", "defaultHours",
                      "pill", "all", "date", "dateCheck", "chips", "dateCost", "dateModal", "slot",
                      "summary", "hint", "several", "total", "severalModal", "severalRow", "settledToggle"]

    connect() {
        this.money = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" })
        this.refresh()
    }

    // ----- the services on top -----

    // Ticking a service at the top puts it where it usually goes (unless some
    // dates already have it from before).
    serviceToggled(event) {
        const service = event.currentTarget.closest("[data-contract-services-target=service]")
        const body = service.querySelector("[data-contract-services-target=body]")
        if (body) body.classList.toggle("hidden", !event.currentTarget.checked)
        const anyOn = this.slotsFor(service.dataset.index).some(slot => slot.querySelector("[data-role=on]")?.checked)
        if (event.currentTarget.checked && !anyOn) this.applyUsual(service)
        this.refresh()
    }

    // A service ticked on a date (its Edit, or several at once) that isn't on
    // the contract yet goes on for those dates only.
    includeFor(service, dates) {
        if (this.included(service)) return
        const include = service.querySelector("[data-contract-services-target=include]")
        include.checked = true
        service.querySelector("[data-contract-services-target=body]")?.classList.remove("hidden")
        this.slotsFor(service.dataset.index).forEach(slot => {
            if (dates.includes(slot.dataset.date) || this.dateRow(slot.dataset.date)?.dataset.locked) return
            const on = slot.querySelector("[data-role=on]")
            if (on) on.checked = false
        })
    }

    // A new price reaches every date that doesn't have its own.
    priceChanged(event) {
        const service = event.currentTarget.closest("[data-contract-services-target=service]")
        const price = event.currentTarget.value
        this.slotsFor(service.dataset.index).forEach(slot => {
            if (this.dateRow(slot.dataset.date)?.dataset.locked) return // settled: stays as it is
            const field = slot.querySelector("[data-role=price]")
            if (field && field.dataset.own !== "1") field.value = price
        })
        this.refresh()
    }

    // "Usually on" puts the service on every date of that kind (or every date,
    // or none), at the usual hours; "Some dates" leaves the dates as they are.
    usualChanged(event) {
        this.applyUsual(event.currentTarget.closest("[data-contract-services-target=service]"))
        this.refresh()
    }

    applyUsual(service) {
        const usual = service.querySelector("[data-contract-services-target=usual]")?.value
        if (!usual || usual === "some") return

        const hours = service.querySelector("[data-contract-services-target=defaultHours]")?.value
        this.slotsFor(service.dataset.index).forEach(slot => {
            const date = this.dateRow(slot.dataset.date)
            if (date?.dataset.locked) return // settled: stays as it is
            const on = slot.querySelector("[data-role=on]")
            if (on) on.checked = usual === "all" || usual === date?.dataset.kind
            const hoursField = slot.querySelector("[data-role=hours]")
            if (hoursField && hours && hoursField.type !== "hidden") hoursField.value = hours
        })
    }

    // New usual hours go on every open date that had the old usual hours; a
    // date given its own hours keeps them, and which dates it's on stays put.
    hoursChanged(event) {
        const input = event.currentTarget
        const service = input.closest("[data-contract-services-target=service]")
        const hours = input.value
        const before = input.dataset.previous ?? input.defaultValue
        input.dataset.previous = hours
        if (!hours) return
        this.slotsFor(service.dataset.index).forEach(slot => {
            if (this.dateRow(slot.dataset.date)?.dataset.locked) return
            const field = slot.querySelector("[data-role=hours]")
            if (field && field.type !== "hidden" && parseFloat(field.value) === parseFloat(before)) field.value = hours
        })
        this.refresh()
    }

    // ----- one date's Edit -----

    openDate(event) {
        const modal = this.dateModal(event.currentTarget.dataset.date)
        if (!modal) return
        modal._snapshot = Array.from(modal.querySelectorAll("input")).map(input => [ input, input.checked, input.value, input.dataset.own ])
        modal.classList.remove("hidden")
        this.refresh()
    }

    cancelDate(event) {
        this.cancelModal(event.currentTarget.closest("[data-contract-services-target=dateModal]"))
    }

    cancelModal(modal) {
        ;(modal?._snapshot || []).forEach(([ input, checked, value, own ]) => {
            input.checked = checked
            input.value = value
            if (own !== undefined) input.dataset.own = own
        })
        modal?.classList.add("hidden")
        this.refresh()
    }

    saveDate(event) {
        const modal = event.currentTarget.closest("[data-contract-services-target=dateModal]")
        modal?.querySelectorAll("[data-contract-services-target=slot]").forEach(slot => {
            if (slot.querySelector("[data-role=on]")?.checked) this.includeFor(this.service(slot.dataset.index), [ slot.dataset.date ])
        })
        modal?.classList.add("hidden")
        this.matchUsual()
        this.refresh()
    }

    slotChanged() {
        this.refresh()
    }

    // A price typed for one date is that date's own from then on.
    slotPriced(event) {
        const field = event.currentTarget
        const slot = field.closest("[data-contract-services-target=slot]")
        field.dataset.own = this.samePrice(field.value, this.linePrice(slot.dataset.index)) ? "0" : "1"
        this.refresh()
    }

    // Settled dates sit collapsed under one line; "Show them" lists them, read-only.
    toggleSettled(event) {
        const rows = this.dateTargets.filter(row => row.dataset.locked)
        const show = rows.some(row => row.classList.contains("hidden"))
        rows.forEach(row => row.classList.toggle("hidden", !show))
        const label = event.currentTarget.querySelector("span") || event.currentTarget
        label.textContent = show ? "Hide them" : "Show them"
    }

    // ----- several dates at once -----

    filter(event) {
        const kind = event.currentTarget.dataset.kind || ""
        this.dateTargets.filter(row => !row.dataset.locked).forEach(row => {
            const hide = kind !== "" && row.dataset.kind !== kind
            row.classList.toggle("hidden", hide)
            if (hide) row.querySelectorAll("[data-contract-services-target=dateCheck]").forEach(box => { box.checked = false })
        })
        if (this.hasAllTarget) this.allTarget.checked = false
        this.pillTargets.forEach(pill => {
            const on = (pill.dataset.kind || "") === kind
            ;[ "border-pink-300", "bg-pink-50", "text-pink-700" ].forEach(c => pill.classList.toggle(c, on))
            ;[ "border-gray-300", "bg-white", "text-gray-700" ].forEach(c => pill.classList.toggle(c, !on))
        })
        this.datesTicked()
    }

    toggleAll(event) {
        const on = event.currentTarget.checked
        this.dateCheckTargets.filter(box => !box.closest("[data-contract-services-target=date]").classList.contains("hidden"))
                             .forEach(box => { box.checked = on })
        this.datesTicked()
    }

    datesTicked() {
        const ticked = this.tickedDates()
        if (this.hasHintTarget) this.hintTarget.classList.toggle("hidden", ticked.length > 0)
        if (this.hasSeveralTarget) {
            this.severalTarget.classList.toggle("hidden", ticked.length === 0)
            const button = this.severalTarget.querySelector("button")
            if (button) button.textContent = ticked.length === 1 ? "Edit the ticked date" : `Edit the ${ticked.length} ticked dates`
        }
    }

    // Starts from what the ticked dates have: a service ticked when every one
    // has it, at the first one's hours and price.
    openSeveral() {
        if (!this.hasSeveralModalTarget) return
        const dates = this.tickedDates()
        this.severalRowTargets.forEach(row => {
            const slots = dates.map(date => this.slot(row.dataset.index, date)).filter(Boolean)
            const onSlots = slots.filter(slot => slot.querySelector("[data-role=on]")?.checked)
            row.querySelector("[data-role=on]").checked = slots.length > 0 && onSlots.length === slots.length
            const first = onSlots[0] || slots[0]
            if (!first) return
            const hours = row.querySelector("[data-role=hours]")
            if (hours) hours.value = first.querySelector("[data-role=hours]")?.value || hours.value
            const price = row.querySelector("[data-role=price]")
            if (price) price.value = first.querySelector("[data-role=price]")?.value || price.value
        })
        this.severalModalTarget.classList.remove("hidden")
    }

    closeSeveral() {
        if (this.hasSeveralModalTarget) this.severalModalTarget.classList.add("hidden")
    }

    saveSeveral() {
        const dates = this.tickedDates()
        this.severalRowTargets.forEach(row => {
            const on = row.querySelector("[data-role=on]").checked
            const hours = row.querySelector("[data-role=hours]")?.value
            const price = row.querySelector("[data-role=price]")?.value
            if (on) this.includeFor(this.service(row.dataset.index), dates)
            dates.forEach(date => {
                const slot = this.slot(row.dataset.index, date)
                if (!slot) return
                slot.querySelector("[data-role=on]").checked = on
                const hoursField = slot.querySelector("[data-role=hours]")
                if (hoursField && hours && hoursField.type !== "hidden") hoursField.value = hours
                const priceField = slot.querySelector("[data-role=price]")
                if (priceField && price !== undefined) {
                    priceField.value = price
                    priceField.dataset.own = this.samePrice(price, this.linePrice(row.dataset.index)) ? "0" : "1"
                }
            })
        })
        this.closeSeveral()
        // Done with those dates: clear the ticks.
        this.dateCheckTargets.forEach(box => { box.checked = false })
        if (this.hasAllTarget) this.allTarget.checked = false
        this.datesTicked()
        this.matchUsual()
        this.refresh()
    }

    // Escape, or a click on the dimmed backdrop, is Cancel.
    escape() {
        this.dateModalTargets.filter(m => !m.classList.contains("hidden")).forEach(m => this.cancelModal(m))
        if (this.hasSeveralModalTarget && !this.severalModalTarget.classList.contains("hidden")) this.closeSeveral()
    }

    backdrop(event) {
        if (event.target !== event.currentTarget) return
        if (event.currentTarget === this.severalModalTarget) this.closeSeveral()
        else this.cancelModal(event.currentTarget)
    }

    // ----- keeping it all in step -----

    refresh() {
        const totals = { incoming: 0, outgoing: 0 }
        const perService = {}

        this.dateTargets.forEach(row => {
            const j = row.dataset.date
            let cost = 0
            let any = false
            const chips = []
            this.slotTargets.filter(slot => slot.dataset.date === j).forEach(slot => {
                const service = this.service(slot.dataset.index)
                const amount = this.slotAmount(slot)
                const amountCell = slot.querySelector("[data-role=amount]")
                const on = slot.querySelector("[data-role=on]")?.checked
                if (amountCell) amountCell.textContent = on ? this.money.format(amount) : ""
                if (!on || !this.included(service)) return

                const hourly = service.dataset.unit === "hourly"
                const hours = parseFloat(slot.querySelector("[data-role=hours]")?.value || "0")
                // A date priced its own way says so on its chip: "Booth Tech 2 hrs · $0/hr".
                const priceField = slot.querySelector("[data-role=price]")
                const own = priceField?.dataset.own === "1"
                const words = [ hourly ? this.hoursWords(hours) : null,
                                own ? `${this.shortMoney(parseFloat(priceField.value) || 0)}${hourly ? "/hr" : ""}` : null ].filter(Boolean).join(" · ")
                const tint = own ? "bg-pink-50 text-pink-800 ring-1 ring-inset ring-pink-200" : "bg-gray-100 text-gray-700"
                chips.push(`<span class="inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-sm ${tint}"><b class="font-medium ${own ? "text-pink-900" : "text-gray-900"}">${this.h(service.dataset.name)}</b>${words ? ` ${words}` : ""}</span>`)
                any = true
                cost += amount
                const direction = service.querySelector("[data-contract-services-target=direction]")?.value || "incoming"
                totals[direction] += amount
                const tally = perService[service.dataset.name] ||= { hours: 0, amount: 0, hourly }
                tally.hours += hours
                tally.amount += amount
            })
            const chipsCell = this.chipsTargets.find(cell => cell.dataset.date === j)
            if (chipsCell) chipsCell.innerHTML = chips.length ? chips.join("") : `<span class="text-sm text-gray-400">None</span>`
            const costCell = this.dateCostTargets.find(cell => cell.dataset.date === j)
            if (costCell) costCell.textContent = any ? this.money.format(cost) : "—"
        })

        if (this.hasSummaryTarget) {
            this.summaryTarget.textContent = Object.entries(perService)
                .map(([ name, t ]) => t.hourly ? `${name} ${this.hoursWords(t.hours)}, ${this.money.format(t.amount)}` : `${name} ${this.money.format(t.amount)}`)
                .join(" · ")
        }
        if (this.hasTotalTarget) {
            const parts = []
            if (totals.incoming > 0) parts.push(`They pay us <b class="tabular-nums">${this.money.format(totals.incoming)}</b>`)
            if (totals.outgoing > 0) parts.push(`We pay them <b class="tabular-nums">${this.money.format(totals.outgoing)}</b>`)
            this.totalTarget.innerHTML = parts.join(" · ")
        }
    }

    // After a date's own edit, each service's "Usually on" says what its dates
    // now add up to: a kind, every date, none, or "Some dates".
    matchUsual() {
        this.serviceTargets.forEach(service => {
            const select = service.querySelector("[data-contract-services-target=usual]")
            if (!select) return
            const on = new Set(this.slotsFor(service.dataset.index).filter(slot => slot.querySelector("[data-role=on]")?.checked)
                                                                   .map(slot => slot.dataset.date))
            const all = this.dateTargets.map(row => row.dataset.date)
            const ofKind = kind => this.dateTargets.filter(row => row.dataset.kind === kind).map(row => row.dataset.date)
            const same = (list) => list.length === on.size && list.every(j => on.has(j))

            let value = "some"
            if (on.size === 0) value = "none"
            else if (same(all)) value = "all"
            else {
                const kinds = [ ...new Set(this.dateTargets.map(row => row.dataset.kind)) ]
                value = kinds.find(kind => same(ofKind(kind))) || "some"
            }
            if (value === "some" && !Array.from(select.options).some(option => option.value === "some")) {
                select.add(new Option("Some dates", "some"))
            }
            select.value = value
        })
    }

    slotAmount(slot) {
        const service = this.service(slot.dataset.index)
        const price = parseFloat(slot.querySelector("[data-role=price]")?.value || "0") || 0
        const hours = parseFloat(slot.querySelector("[data-role=hours]")?.value || "1") || 0
        return service?.dataset.unit === "hourly" ? price * hours : price
    }

    included(service) {
        return !!service?.querySelector("[data-contract-services-target=include]")?.checked
    }

    linePrice(index) {
        return this.service(index)?.querySelector("[data-contract-services-target=price]")?.value
    }

    samePrice(a, b) {
        return Math.round((parseFloat(a) || 0) * 100) === Math.round((parseFloat(b) || 0) * 100)
    }

    tickedDates() {
        return this.dateCheckTargets.filter(box => box.checked).map(box => box.dataset.date)
    }

    service(index) { return this.serviceTargets.find(s => s.dataset.index === String(index)) }
    slotsFor(index) { return this.slotTargets.filter(s => s.dataset.index === String(index)) }
    slot(index, date) { return this.slotTargets.find(s => s.dataset.index === String(index) && s.dataset.date === String(date)) }
    dateRow(date) { return this.dateTargets.find(row => row.dataset.date === String(date)) }
    dateModal(date) { return this.dateModalTargets.find(m => m.dataset.date === String(date)) }

    // $0, $40, $42.50
    shortMoney(n) {
        return n % 1 === 0 ? `$${n.toLocaleString("en-US")}` : this.money.format(n)
    }

    hoursWords(hours) {
        const n = Math.round(hours * 10) / 10
        return `${n} ${n === 1 ? "hr" : "hrs"}`
    }

    h(text) {
        const div = document.createElement("div")
        div.textContent = String(text ?? "")
        return div.innerHTML
    }
}
