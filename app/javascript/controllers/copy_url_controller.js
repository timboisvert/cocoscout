import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["button"]

    copy(event) {
        event.preventDefault()

        // Get the URL from the button wrapper div
        const url = this.buttonTarget.dataset.url

        navigator.clipboard.writeText(url).then(() => {
            // Find the button's text span
            const textSpan = this.buttonTarget.querySelector('span')

            if (textSpan) {
                const originalText = textSpan.textContent
                textSpan.textContent = 'Copied!'

                setTimeout(() => {
                    textSpan.textContent = originalText
                }, 2000)
            }
        }).catch(err => {
            console.error('Failed to copy URL:', err)
        })
    }
}
