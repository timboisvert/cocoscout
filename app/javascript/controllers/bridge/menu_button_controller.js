import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Bridge Component: where the app's floating Coco button belongs on this
// page (Tim, 2026-11-06). The button is native, drawn over the page in the
// bottom right corner, and it used to stay put while every pinned bar made
// room for it. Now the button gets itself out of the way. The page looks at
// what is really under the button's corner and tells the app two things:
//
//   rise  how far above the bottom of the page the button must sit to clear
//         a bar pinned there (0 with none), in the page's own pixels
//   away  the button should not be there at all: the reader is scrolling
//         down, or a sheet or modal is over the page
//
// The app only obeys (MenuButtonComponent on iOS and Android), so how this
// behaves is changed here, with a deploy, never with an app release.
//
// No view marks anything for this. A bar is found because it is pinned
// (position fixed, or sticky and stuck) at the bottom under the button; a
// sheet because it is fixed and covers half the screen or more. Only app
// builds with the component load this (the bridge reads the user agent);
// older builds keep their button still and their bars keep room for it
// (NativeAppHelper#coco_button_in_the_way?).
export default class extends BridgeComponent {
  static component = "menu-button"

  // The button's corner, measured in from the right and up from the bottom:
  // it is 60 across and 20 in, and its top is under 90 up, on both phones.
  static columns = [ 26, 50, 74 ]
  static rows = [ 20, 50, 80 ]
  // A scroll counts once it has gone this far one way...
  static travel = 12
  // ...and never this close to the top or the end of the page, where the
  // button always shows (the end is where the page leaves room for it).
  static edge = 8

  connect() {
    super.connect()
    this.sent = null
    this.scrolledAway = false
    this.rise = 0
    this.covered = false
    this.marks = new WeakMap()

    this.onScroll = this.scrolled.bind(this)
    this.onChange = () => this.measureSoon()
    this.onShow = () => { if (!document.hidden) { this.sent = null; this.measureSoon() } }

    document.addEventListener("scroll", this.onScroll, { capture: true, passive: true })
    window.addEventListener("resize", this.onChange)
    document.addEventListener("transitionend", this.onChange, true)
    document.addEventListener("animationend", this.onChange, true)
    document.addEventListener("toggle", this.onChange, true)
    // Back in front (a sheet over this page closed): the app may have been
    // following another page since, so say it again.
    document.addEventListener("visibilitychange", this.onShow)
    window.addEventListener("pageshow", this.onShow)

    // Bars and sheets come and go by a class, a hidden attribute or new
    // markup; none of them announce it.
    this.observer = new MutationObserver(this.onChange)
    this.observer.observe(document.body, { subtree: true, childList: true, attributes: true,
                                           attributeFilter: [ "class", "style", "hidden", "open" ] })

    this.measure()
    // Once more when the page has settled (fonts, frames, late bars).
    this.settle = setTimeout(() => this.measure(), 400)
  }

  disconnect() {
    document.removeEventListener("scroll", this.onScroll, { capture: true })
    window.removeEventListener("resize", this.onChange)
    document.removeEventListener("transitionend", this.onChange, true)
    document.removeEventListener("animationend", this.onChange, true)
    document.removeEventListener("toggle", this.onChange, true)
    document.removeEventListener("visibilitychange", this.onShow)
    window.removeEventListener("pageshow", this.onShow)
    this.observer?.disconnect()
    cancelAnimationFrame(this.frame)
    clearTimeout(this.settle)
    clearTimeout(this.trailing)
    super.disconnect()
  }

  // Scrolling down a page (or a panel as tall as half the screen) sends the
  // button away; scrolling up, the top, and the end bring it back.
  scrolled(event) {
    const page = document.scrollingElement
    const scroller = event.target === document ? page : event.target
    if (!(scroller instanceof Element)) return
    const height = scroller === page ? window.innerHeight : scroller.clientHeight

    if (height >= window.innerHeight / 2) {
      const y = scroller.scrollTop
      const end = scroller.scrollHeight - height
      const mark = this.marks.has(scroller) ? this.marks.get(scroller) : y
      const { travel, edge } = this.constructor
      let away = this.scrolledAway
      if (y <= edge || y >= end - edge) away = false
      else if (y - mark > travel) away = true
      else if (mark - y > travel) away = false

      // The mark follows the scroll once it has counted, so turning round
      // is noticed after the same short distance.
      if (!this.marks.has(scroller) || Math.abs(y - mark) > travel || away !== this.scrolledAway) this.marks.set(scroller, y)
      if (away !== this.scrolledAway) {
        this.scrolledAway = away
        this.place()
      }
    }

    // What's pinned can change as the page moves (a sticky bar lets go), but
    // it doesn't need looking at on every frame of a scroll.
    clearTimeout(this.trailing)
    this.trailing = setTimeout(() => this.measure(), 120)
  }

  measureSoon() {
    cancelAnimationFrame(this.frame)
    this.frame = requestAnimationFrame(() => this.measure())
  }

  // What is under the button's corner right now.
  measure() {
    const width = window.innerWidth
    const height = window.innerHeight
    if (!width || !height) return

    let covered = this.modalDialogOpen
    let rise = 0
    if (!covered) {
      for (const column of this.constructor.columns) {
        for (const row of this.constructor.rows) {
          const found = this.pinnedAt(width - column, height - row, height)
          if (found === true) covered = true
          else rise = Math.max(rise, found)
        }
      }
    }
    this.covered = covered
    this.rise = covered ? 0 : Math.round(rise)
    this.place()
  }

  // true: a sheet or modal covers this point. Otherwise how far above the
  // bottom of the page the thing pinned here reaches (0: nothing pinned).
  pinnedAt(x, y, height) {
    let fixed = null
    let dialog = false
    let top = height
    let stuck = 0
    for (let node = document.elementFromPoint(x, y); node && node !== document.documentElement; node = node.parentElement) {
      const style = getComputedStyle(node)
      if (node.matches("dialog, [role='dialog'], [role='alertdialog'], [aria-modal='true']")) dialog = true
      if (style.position === "fixed") {
        // The outermost one decides: a sheet's own pinned footer is still a
        // sheet. Whatever it holds counts with it (a sheet drawn from inside
        // a bar stands taller than the bar).
        fixed = node
        top = Math.min(top, node.getBoundingClientRect().top)
      } else if (!fixed) {
        top = Math.min(top, node.getBoundingClientRect().top)
        if (style.position === "sticky" && style.bottom !== "auto" && !stuck) {
          const box = node.getBoundingClientRect()
          const rest = height - (parseFloat(style.bottom) || 0)
          if (Math.abs(box.bottom - rest) < 2 && box.height < height / 2) stuck = height - box.top
        }
      }
    }
    if (!fixed) return stuck
    if (dialog || height - top >= height / 2) return true

    return fixed.getBoundingClientRect().bottom >= height - 48 ? height - top : 0
  }

  get modalDialogOpen() {
    try { return !!document.querySelector("dialog:modal") } catch { return false }
  }

  // Only a change is news.
  place() {
    const next = { rise: this.rise, away: this.covered || this.scrolledAway }
    if (this.sent && this.sent.rise === next.rise && this.sent.away === next.away) return
    this.sent = next
    this.send("place", next)
  }
}
