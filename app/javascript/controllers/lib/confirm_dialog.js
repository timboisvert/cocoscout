// Promise-based in-page confirmation dialog.
//
// Replaces native window.confirm() with a styled modal that matches the
// CocoScout confirmation modal (pink gradient header, pink confirm button,
// white cancel button — see app/views/shared/_confirm_modal.html.erb).
//
// Usage inside a Stimulus controller method (make the method `async`):
//
//   import { confirmDialog } from "controllers/lib/confirm_dialog"
//
//   async remove(event) {
//     if (!(await confirmDialog({
//       title: "Remove video?",
//       message: "Remove this video?",
//       confirmText: "Remove"
//     }))) return
//     // ...proceed with the action...
//   }
//
// Resolves to true when confirmed, false when cancelled (Cancel button,
// close X, backdrop click, or Escape).

const BASE_BTN =
  "inline-flex items-center justify-center gap-2 font-medium rounded transition-colors cursor-pointer whitespace-nowrap px-3 py-1.5 text-sm sm:px-5 sm:py-2.5 sm:h-10"
const CANCEL_BTN = `${BASE_BTN} bg-white border border-gray-300 hover:bg-gray-50 text-gray-700`
const CONFIRM_BTN = `${BASE_BTN} bg-pink-500 hover:bg-pink-600 text-white`

export function confirmDialog({
  title = "Are you sure?",
  message = "",
  confirmText = "Confirm",
  cancelText = "Cancel"
} = {}) {
  return new Promise((resolve) => {
    const overlay = document.createElement("div")
    // Sits above app modals (which range up to ~z-[70]) so a confirm triggered
    // from inside a modal — e.g. switching availability mode — appears on top,
    // not hidden behind it.
    overlay.className = "fixed inset-0 bg-black/50 z-[100] flex items-center justify-center p-4"
    overlay.innerHTML = `
      <div class="bg-white rounded-xl shadow-2xl w-full max-w-md mx-4 overflow-hidden" data-confirm-panel>
        <div class="flex items-center justify-between bg-gradient-to-r from-pink-500 to-pink-600 px-6 py-4">
          <h3 class="text-lg font-semibold text-white" data-confirm-title></h3>
          <button type="button" data-confirm-close
                  class="rounded-full p-1 text-white/80 hover:text-white hover:bg-white/10 transition-colors cursor-pointer">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
            </svg>
          </button>
        </div>
        <div class="px-6 py-5 text-sm text-gray-600" data-confirm-message></div>
        <div class="px-6 py-4 bg-gray-50 border-t border-gray-200 flex items-center justify-end gap-2">
          <button type="button" data-confirm-cancel class="${CANCEL_BTN}"></button>
          <button type="button" data-confirm-ok class="${CONFIRM_BTN}"></button>
        </div>
      </div>
    `

    // Set text content (avoids HTML injection from interpolated names).
    overlay.querySelector("[data-confirm-title]").textContent = title
    overlay.querySelector("[data-confirm-message]").textContent = message
    overlay.querySelector("[data-confirm-cancel]").textContent = cancelText
    overlay.querySelector("[data-confirm-ok]").textContent = confirmText

    const cleanup = (result) => {
      document.removeEventListener("keydown", onKey)
      overlay.remove()
      resolve(result)
    }
    const onKey = (event) => {
      if (event.key === "Escape") cleanup(false)
    }

    overlay.addEventListener("click", (event) => {
      if (event.target === overlay) cleanup(false)
    })
    overlay.querySelector("[data-confirm-close]").addEventListener("click", () => cleanup(false))
    overlay.querySelector("[data-confirm-cancel]").addEventListener("click", () => cleanup(false))
    overlay.querySelector("[data-confirm-ok]").addEventListener("click", () => cleanup(true))

    document.addEventListener("keydown", onKey)
    document.body.appendChild(overlay)
    overlay.querySelector("[data-confirm-ok]").focus()
  })
}
