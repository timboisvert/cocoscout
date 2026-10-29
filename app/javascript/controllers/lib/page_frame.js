// Go to another view of this same page (a toggle, a select) from script: into
// the page frame (page_frame_controller) when there is one, so only the page's
// content changes; otherwise an ordinary Turbo visit.
//   visitPage(url)                      a new history entry on the web
//   visitPage(url, { action: "replace" })
export function visitPage(url, { action } = {}) {
    const event = new CustomEvent("page-frame:visit", { cancelable: true, detail: { url: String(url), action } })
    window.dispatchEvent(event)
    if (event.defaultPrevented) return
    if (window.Turbo) window.Turbo.visit(String(url), action ? { action } : {})
    else window.location.href = String(url)
}
