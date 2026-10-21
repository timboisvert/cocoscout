import { Controller } from "@hotwired/stimulus"

// A grid of tiles whose tap, on a phone, opens that tile's actions in a
// shared sheet (V1.1 plan §4): the profile link and Remove. With a mouse
// the tile is a plain link and Remove shows on hover, so the sheet never
// opens there.
export default class extends Controller {
    static targets = ["profileLink", "removeButton"]
    static values = { id: String }

    open(event) {
        if (window.matchMedia("(min-width: 640px)").matches) return
        event.preventDefault()
        const tile = event.currentTarget
        const sheet = this.sheet()
        if (!sheet) return
        const title = sheet.querySelector("h3")
        if (title) title.textContent = tile.dataset.tileName || "Talent pool"
        const profile = sheet.querySelector("[data-tile-sheet-target='profileLink']")
        if (profile) profile.href = tile.href
        const remove = sheet.querySelector("[data-tile-sheet-target='removeButton']")
        if (remove) {
            remove.classList.toggle("hidden", tile.dataset.tileRemove !== "true")
            remove.dataset.personId = tile.dataset.tilePersonId
            remove.dataset.memberType = tile.dataset.tileMemberType
            remove.dataset.memberName = tile.dataset.tileName
        }
        sheet.classList.remove("hidden")
    }

    close() {
        this.sheet()?.classList.add("hidden")
    }

    sheet() {
        return document.getElementById(this.idValue)
    }
}
