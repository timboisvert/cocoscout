import { Controller } from "@hotwired/stimulus"

// Shows how a show's event image will be cut in each place it appears — the
// show page (16:9) and link previews when it's shared (about 1.91:1) — as
// soon as a picture is chosen, and warns when it's smaller than the 1200×675
// minimum. Nothing is cropped for real: every place fills its frame from the
// middle of the picture.
export default class extends Controller {
    static targets = ["input", "preview", "frame", "warning"]
    static values = { minWidth: { type: Number, default: 1200 }, minHeight: { type: Number, default: 675 } }

    disconnect() {
        if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
    }

    choose() {
        const file = this.inputTarget.files?.[0]
        if (!file) return

        if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
        this.objectUrl = URL.createObjectURL(file)
        this.frameTargets.forEach((img) => { img.src = this.objectUrl })
        this.previewTarget.classList.remove("hidden")

        const probe = new Image()
        probe.onload = () => {
            const small = probe.naturalWidth < this.minWidthValue || probe.naturalHeight < this.minHeightValue
            this.warningTarget.textContent = small
                ? `This picture is ${probe.naturalWidth}×${probe.naturalHeight}. It may look soft; ${this.minWidthValue}×${this.minHeightValue} or larger works best.`
                : ""
            this.warningTarget.classList.toggle("hidden", !small)
        }
        probe.src = this.objectUrl
    }
}
