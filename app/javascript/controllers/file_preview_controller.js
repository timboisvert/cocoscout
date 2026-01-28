import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["input", "preview", "label"]

    preview(event) {
        const file = event.target.files[0]
        if (!file) return

        // Update label to show file name
        if (this.hasLabelTarget) {
            this.labelTarget.textContent = file.name
        }

        // If it's an image, show preview
        if (file.type.startsWith("image/") && this.hasPreviewTarget) {
            const reader = new FileReader()
            reader.onload = (e) => {
                this.previewTarget.innerHTML = `
          <img src="${e.target.result}"
               alt="Preview"
               class="rounded shadow-sm object-contain max-h-[100px] max-w-[120px] border border-gray-200" />
        `
            }
            reader.readAsDataURL(file)
        }
    }
}
