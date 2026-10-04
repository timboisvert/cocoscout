import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["button"]

    copy(event) {
        event.preventDefault()

        // The URL sits on the wrapper around whichever Copy was pressed
        // (the main address, or the full one under a short link).
        const wrapper = event.currentTarget.closest("[data-url]") || this.buttonTarget
        const url = wrapper.dataset.url

        navigator.clipboard.writeText(url).then(() => {
            // Find the button's text span
            const textSpan = wrapper.querySelector('span')

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
