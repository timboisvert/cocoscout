import { Controller } from "@hotwired/stimulus"
import { visitPage } from "controllers/lib/page_frame"

// The page's own content: <turbo-frame id="page" target="_top"> around the
// layout's yield (application and native layouts). A link or GET form that
// stays on this page and only changes its query (a filter chip, a tab, the
// next month, a page of results, a day in a strip) loads into this frame
// instead of loading the whole page: the navigation and the scroll stay put,
// the app stays on the same screen (Turbo never proposes a visit to it), and
// the address follows along. Anything that goes somewhere else loads the page
// as usual, and so does a link or form marked data-page-frame="false".
//
// Scroll: a new page of results (a "page" param) or a control marked
// data-page-frame-scroll="top" goes back to the top, like a page load would.
//
// The phone day strip (shared/day_strip) adds one thing: a tap moves the pink
// day at once (pick), and the strip on screen is kept as it is (Tim,
// 2026-10-29); a swipe past its ends or the "Pick a day" sheet brings a fresh
// strip around the new day.
const NATIVE = /(Turbo|Hotwire) Native/.test(navigator.userAgent)

export default class extends Controller {
    connect() {
        this.clicked = this.clicked.bind(this)
        this.submitted = this.submitted.bind(this)
        this.visitRequested = this.visitRequested.bind(this)
        // Capture: ahead of Turbo, which decides on the bubble.
        document.addEventListener("click", this.clicked, true)
        document.addEventListener("submit", this.submitted, true)
        window.addEventListener("page-frame:visit", this.visitRequested)
        this.nav = {}
    }

    disconnect() {
        document.removeEventListener("click", this.clicked, true)
        document.removeEventListener("submit", this.submitted, true)
        window.removeEventListener("page-frame:visit", this.visitRequested)
    }

    // --- Into the frame ----------------------------------------------------

    // turbo:before-prefetch (on hover or touch): a link that loads into this
    // frame gets its own request, so a page prefetch would be thrown away.
    prefetching(event) {
        const link = event.target
        if (this.intoFrame(link)) event.preventDefault()
    }

    clicked(event) {
        if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
        const link = event.target.closest?.("a[href]")
        const url = this.intoFrame(link)
        if (url) this.prepare(link, url, link)
    }

    // The link's URL when it should load into this frame; otherwise null.
    intoFrame(link) {
        if (!(link instanceof HTMLAnchorElement) || !link.hasAttribute("href") || !this.owns(link)) return null
        if (link.hasAttribute("download") || (link.target && link.target !== "_self")) return null
        if (link.hasAttribute("data-turbo-method") || link.hasAttribute("data-method") || link.hasAttribute("data-turbo-stream")) return null
        if (/^(#|javascript:)/i.test(link.getAttribute("href"))) return null
        const url = new URL(link.href, window.location.href)
        return this.samePage(url, { hash: true }) ? url : null
    }

    submitted(event) {
        const form = event.target
        if (!(form instanceof HTMLFormElement) || !this.owns(form)) return
        const submitter = event.submitter
        const method = (submitter?.getAttribute("formmethod") || form.getAttribute("method") || "get").toLowerCase()
        if (method !== "get") return
        const target = submitter?.getAttribute("formtarget") || form.getAttribute("target")
        if (target && target !== "_self") return
        const url = new URL(submitter?.getAttribute("formaction") || form.getAttribute("action") || window.location.href, window.location.href)
        if (!this.samePage(url)) return
        this.prepare(form, url, submitter)
    }

    // From script (visitPage in controllers/lib/page_frame): a URL on this page.
    visitRequested(event) {
        const url = new URL(event.detail.url, window.location.href)
        if (!this.samePage(url)) return
        event.preventDefault()
        this.nav = this.navFor(url, event.detail.action)
        this.keepStripId = null
        window.Turbo.visit(url.href, { frame: this.element.id })
    }

    // A <select> that picks another view of this page:
    //   data-action="change->page-frame#choose" data-page-frame-param="period"
    // sets that param on this page's address (keeping the others; the base
    // can be data-page-frame-url) and loads it here.
    choose(event) {
        const select = event.currentTarget
        let url = new URL(select.dataset.pageFrameUrl || window.location.href, window.location.href)
        if (url.pathname === window.location.pathname) url = new URL(window.location.href)
        url.searchParams.set(select.dataset.pageFrameParam, select.value)
        for (const key of [ ...url.searchParams.keys() ]) if (/(^|_)page$/.test(key)) url.searchParams.delete(key)
        visitPage(url)
    }

    // Only what's in this frame (not in a frame of its own), never opted out.
    owns(element) {
        if (element.closest("turbo-frame") !== this.element) return false
        if (element.closest("[data-page-frame='false'], [data-turbo='false']")) return false
        const frame = element.getAttribute("data-turbo-frame")
        return !frame || frame === this.element.id
    }

    samePage(url, { hash = false } = {}) {
        if (url.origin !== window.location.origin || url.pathname !== window.location.pathname) return false
        // A jump to an anchor on this very page is the browser's to do.
        return !(hash && url.hash && url.search === window.location.search)
    }

    prepare(element, url, submitter) {
        const action = submitter?.getAttribute("data-turbo-action") || element.getAttribute("data-turbo-action")
        // A frame load with an action would become a visit (a new screen in
        // the app); the history is ours to keep (loaded).
        element.removeAttribute("data-turbo-action")
        submitter?.removeAttribute("data-turbo-action")
        element.setAttribute("data-turbo-frame", this.element.id)
        this.nav = this.navFor(url, action, element)
        this.keepStripId = null // a strip tap sets it again (pick, on the bubble)
    }

    navFor(url, action, element) {
        const pageParam = (params) => [ ...params ].filter(([ key ]) => /(^|_)page$/.test(key)).map(String).join("&")
        const here = new URL(window.location.href)
        return {
            history: action === "replace" || NATIVE ? "replace" : "push",
            top: pageParam(url.searchParams) !== pageParam(here.searchParams) || !!element?.closest("[data-page-frame-scroll='top']")
        }
    }

    // --- The response --------------------------------------------------------

    // turbo:before-fetch-response. Somewhere else after all (a redirect, a
    // signed-out session)? Then that page loads, whole.
    fetched(event) {
        if (event.target !== this.element) return
        const response = event.detail.fetchResponse
        const url = new URL(response.location)
        if (url.pathname !== window.location.pathname) {
            event.preventDefault()
            window.Turbo.visit(url.href)
            return
        }
        this.nav.url = url
    }

    // turbo:before-frame-render
    beforeRender(event) {
        if (event.target !== this.element) return
        const active = document.activeElement
        this.focus = active?.name && this.element.contains(active) && active.matches("input, textarea, select")
            ? { name: active.name, start: active.selectionStart, end: active.selectionEnd }
            : null
        const id = this.keepStripId
        this.keepStripId = null
        if (!id) return
        const current = document.getElementById(id)
        const incoming = event.detail.newFrame.querySelector(`#${CSS.escape(id)}`)
        // A copy of the strip on screen stands in for the new one, so it never blinks out.
        if (current && incoming) incoming.replaceWith(current.cloneNode(true))
    }

    // turbo:frame-load
    loaded(event) {
        if (event.target !== this.element) return
        const { url = this.element.src && new URL(this.element.src, window.location.href), history: how = "replace", top } = this.nav
        this.nav = {}
        const session = window.Turbo?.session
        if (url && session) {
            if (how === "push") session.history.push(url, crypto.randomUUID?.() ?? String(Date.now()))
            else session.history.replace(url, session.history.restorationIdentifier)
            session.view.lastRenderedLocation = url
        }
        if (top) window.scrollTo({ top: 0 })
        this.restoreFocus()
    }

    restoreFocus() {
        if (!this.focus) return
        const field = this.element.querySelector(`[name="${CSS.escape(this.focus.name)}"]`)
        this.focus = null
        if (!field) return
        field.focus({ preventScroll: true })
        try { field.setSelectionRange?.(field.value.length, field.value.length) } catch (_) { /* not a text field */ }
    }

    // --- The phone day strip -----------------------------------------------

    // A day in the strip (data-action="page-frame#pick"): the pink day moves
    // there now; the frame load keeps the strip.
    pick(event) {
        const link = event.currentTarget
        if (link.getAttribute("aria-current") === "date") {
            event.preventDefault()
            return
        }
        const strip = link.closest("[data-day-strip-keep]")
        if (!strip) return
        strip.querySelectorAll("a[data-strip-day]").forEach((a) => this.mark(a, a === link))
        const title = strip.querySelector("[data-day-title]")
        if (title) title.textContent = link.dataset.label
        strip.querySelector("[data-phone-day-title]")?.setAttribute("aria-label", `${link.dataset.titleLabel}: pick another day`)
        this.keepStripId = strip.id
    }

    mark(link, on) {
        if (on) link.setAttribute("aria-current", "date")
        else link.removeAttribute("aria-current")
        for (const el of [ link, ...link.querySelectorAll("[data-day-on]") ]) {
            const [ add, remove ] = on ? [ el.dataset.dayOn, el.dataset.dayOff ] : [ el.dataset.dayOff, el.dataset.dayOn ]
            el.classList.remove(...this.classes(remove))
            el.classList.add(...this.classes(add))
        }
    }

    classes(list) {
        return (list || "").split(/\s+/).filter(Boolean)
    }
}
