import { Controller } from "@hotwired/stimulus"

// Steps through the slides of a product tour inside a modal.
//
// This controller owns *only* the stepping. Opening and closing the modal
// stays with the generic `modal` controller, which is already on the same
// wrapper element — so a tour modal carries data-controller="modal product-tour".
//
// Because `modal` fires no open/close event, we reset on every close path
// instead of on open (see the data-action wiring in the tour partial). That way
// reopening the tour always starts at step one.
//
// Note the Back/Next controls are wrapped in plain <div>s that we toggle rather
// than hiding the buttons themselves: shared/button renders `inline-flex`,
// which beats Tailwind's `hidden` on the same element.
export default class extends Controller {
    static targets = ["slide", "dot", "counter", "backWrap", "nextWrap", "ctaWrap"]
    static values = { index: { type: Number, default: 0 } }

    connect() {
        this.show()
    }

    next() {
        if (this.indexValue < this.slideTargets.length - 1) {
            this.indexValue++
            this.show()
        }
    }

    back() {
        if (this.indexValue > 0) {
            this.indexValue--
            this.show()
        }
    }

    reset() {
        this.indexValue = 0
        this.show()
    }

    show() {
        const last = this.slideTargets.length - 1

        this.slideTargets.forEach((slide, i) => {
            slide.classList.toggle("hidden", i !== this.indexValue)
        })

        this.dotTargets.forEach((dot, i) => {
            dot.classList.toggle("bg-pink-500", i === this.indexValue)
            dot.classList.toggle("bg-slate-300", i !== this.indexValue)
        })

        if (this.hasCounterTarget) {
            this.counterTarget.textContent = `${this.indexValue + 1} of ${this.slideTargets.length}`
        }

        // Back keeps its space on the first step so the footer doesn't jump.
        if (this.hasBackWrapTarget) {
            this.backWrapTarget.classList.toggle("invisible", this.indexValue === 0)
        }

        // On the last step, Next gives way to the signup call to action.
        if (this.hasNextWrapTarget) {
            this.nextWrapTarget.classList.toggle("hidden", this.indexValue === last)
        }
        if (this.hasCtaWrapTarget) {
            this.ctaWrapTarget.classList.toggle("hidden", this.indexValue !== last)
        }
    }
}
