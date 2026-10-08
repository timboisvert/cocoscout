import { Controller } from "@hotwired/stimulus"

// One of an event's two pictures on its Visual Assets tab: a chosen file
// shows at once, whole, and "Use the production's" goes back to the
// production's picture. Either takes effect when the form is saved.
export default class extends Controller {
    static targets = ["input", "frame", "empty", "removeFlag", "status", "useProduction", "warning"]
    static values = {
        inheritedSrc: String,
        inheritedWords: String,
        minWidth: { type: Number, default: 0 },
        minHeight: { type: Number, default: 0 }
    }

    disconnect() {
        if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
    }

    choose() {
        const file = this.inputTarget.files?.[0]
        if (!file) return

        if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
        this.objectUrl = URL.createObjectURL(file)
        this.show(this.objectUrl)
        if (this.hasRemoveFlagTarget) this.removeFlagTarget.value = "0"
        this.say("This picture is used once you save.")
        this.checkSize()
    }

    useProduction(event) {
        event.preventDefault()
        this.inputTarget.value = ""
        if (this.hasRemoveFlagTarget) this.removeFlagTarget.value = "1"
        this.show(this.inheritedSrcValue)
        if (this.hasUseProductionTarget) this.useProductionTarget.classList.add("hidden")
        if (this.hasWarningTarget) this.warningTarget.classList.add("hidden")
        this.say(`${this.inheritedWordsValue} once you save.`)
    }

    show(src) {
        const has = Boolean(src)
        this.frameTarget.classList.toggle("hidden", !has)
        if (has) this.frameTarget.src = src
        if (this.hasEmptyTarget) this.emptyTarget.classList.toggle("hidden", has)
    }

    say(words) {
        if (!this.hasStatusTarget) return
        this.statusTarget.textContent = words
        this.statusTarget.classList.remove("hidden")
    }

    checkSize() {
        if (!this.hasWarningTarget || !this.minWidthValue) return

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
