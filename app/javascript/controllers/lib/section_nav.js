// How a page's sections show which one is open, for the controllers that
// switch panels in place (tabs, staff-edit): the side list's line
// (shared/section_list) and the phone sheet's row (shared/section_picker).

// A line of the side list. Its resting classes are in data-idle-class.
export function markListItem(item, active) {
    const idle = (item.dataset.idleClass || "text-gray-600 hover:bg-gray-100").split(" ").filter(Boolean)
    for (const name of ["bg-pink-100", "text-pink-600", "font-semibold"]) item.classList.toggle(name, active)
    for (const name of idle) item.classList.toggle(name, !active)
    if (active) item.setAttribute("aria-current", "true"); else item.removeAttribute("aria-current")
}

// A row of the phone's sheet; the open one also names the row that opens the sheet.
export function markSheetItem(item, active, label) {
    item.classList.toggle("text-pink-600", active)
    item.classList.toggle("font-medium", active)
    item.classList.toggle("text-gray-800", !active)
    item.querySelector("[data-section-check]")?.classList.toggle("hidden", !active)
    if (active) item.setAttribute("aria-current", "true"); else item.removeAttribute("aria-current")
    const name = item.querySelector("[data-section-name]")
    if (active && name && label) label.innerHTML = name.innerHTML
}
