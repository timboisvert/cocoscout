import { Controller } from "@hotwired/stimulus"

// The page colors (manage/ticketing/page_colors_fields): each color's well
// and its hex kept in step, one reset (shown once any color differs from
// what this level inherits) that puts all four back, and the little page
// beside them showing how the four look together.
export default class extends Controller {
    static targets = ["well", "hex", "preview", "reset"]

    fromWell(event) {
        this.set(event.target.dataset.key, event.target.value, { skipWell: true })
    }

    fromHex(event) {
        let value = event.target.value.trim().toLowerCase()
        if (/^[0-9a-f]{6}$/.test(value)) value = `#${value}`
        if (!/^#[0-9a-f]{6}$/.test(value)) return

        this.set(event.target.dataset.key, value, { skipHex: true })
    }

    reset() {
        this.wellTargets.forEach((well) => this.set(well.dataset.key, well.dataset.reset))
    }

    set(key, value, { skipWell = false, skipHex = false } = {}) {
        const well = this.well(key)
        const hex = this.hexTargets.find((input) => input.dataset.key === key)
        if (well && !skipWell) well.value = value
        if (hex && !skipHex) hex.value = value
        this.paint()
    }

    well(key) {
        return this.wellTargets.find((input) => input.dataset.key === key)
    }

    paint() {
        if (this.hasResetTarget) {
            const changed = this.wellTargets.some((well) => well.value.toLowerCase() !== well.dataset.reset)
            this.resetTarget.classList.toggle("hidden", !changed)
        }
        if (!this.hasPreviewTarget) return

        const color = (key) => this.well(key).value
        const style = this.previewTarget.style
        style.setProperty("--page-bg", color("background"))
        style.setProperty("--page-heading", color("heading"))
        style.setProperty("--page-text", color("text"))
        style.setProperty("--page-button", color("button"))
        style.setProperty("--page-button-ink", this.dark(color("button")) ? "#ffffff" : "#111827")
        style.setProperty("--page-accent", this.accent(color("button")))
    }

    // The same as PageColors#accent: the button color, or a darker shade of
    // it when it's too light to read on white.
    accent(hex) {
        if (this.dark(hex)) return hex
        return "#" + hex.slice(1).match(/../g).map((pair) => Math.round(parseInt(pair, 16) * 0.45).toString(16).padStart(2, "0")).join("")
    }

    // The same test as PageColors.dark?: relative luminance under 0.4.
    dark(hex) {
        const [r, g, b] = hex.slice(1).match(/../g).map((pair) => {
            const c = parseInt(pair, 16) / 255
            return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
        })
        return 0.2126 * r + 0.7152 * g + 0.0722 * b < 0.4
    }
}
