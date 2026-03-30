import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="fee-calculator"
export default class extends Controller {
    static targets = [
        "priceInput", "earlyBirdInput",
        "breakdown",
        "promoInput", "promoStatus", "promoHidden",
        "promoModal", "promoLink", "promoAppliedBadge",
        "feeRow", "feeLabel", "feeDetails", "feeChevron",
        "registrationPrice", "cocoscoutFee", "producerNet", "stripeFee", "stripeFeeLabel", "platformFee",
        "earlyBirdNet"
    ]

    static values = {
        validateUrl: String,
        cocoscoutFeePercent: { type: Number, default: 5.0 },
        stripeFeePercent: { type: Number, default: 2.9 },
        stripeFeeCents: { type: Number, default: 30 },
        promoApplied: { type: Boolean, default: false }
    }

    connect() {
        this.calculate()
    }

    calculate() {
        const price = this.hasPriceInputTarget ? (parseFloat(this.priceInputTarget.value) || 0) : 0

        if (price <= 0) {
            if (this.hasBreakdownTarget) this.breakdownTarget.classList.add("hidden")
            return
        }

        if (this.hasBreakdownTarget) this.breakdownTarget.classList.remove("hidden")

        const feePercent = this.promoAppliedValue ? 0 : this.cocoscoutFeePercentValue
        const cocoscoutFee = price * (feePercent / 100)
        const producerNet = price - cocoscoutFee
        const stripeFee = price * (this.stripeFeePercentValue / 100) + (this.stripeFeeCentsValue / 100)

        const platformFee = Math.max(cocoscoutFee - stripeFee, 0)

        if (this.hasRegistrationPriceTarget) this.registrationPriceTarget.textContent = this.fmt(price)
        if (this.hasCocoscoutFeeTarget) this.cocoscoutFeeTarget.textContent = this.fmt(cocoscoutFee)
        if (this.hasFeeLabelTarget) {
            this.feeLabelTarget.textContent = feePercent > 0
                ? `CocoScout fee (${feePercent}% — includes processing fees)`
                : "CocoScout fee (waived)"
        }
        if (this.hasProducerNetTarget) this.producerNetTarget.textContent = this.fmt(producerNet)
        if (this.hasStripeFeeTarget) this.stripeFeeTarget.textContent = this.fmt(stripeFee)
        if (this.hasPlatformFeeTarget) this.platformFeeTarget.textContent = this.fmt(platformFee)

        // Style fee row based on promo
        if (this.hasFeeRowTarget) {
            this.feeRowTarget.classList.toggle("text-green-600", this.promoAppliedValue)
            this.feeRowTarget.classList.toggle("text-gray-600", !this.promoAppliedValue)
        }
        // When fee is waived, auto-expand details to show CocoScout is covering Stripe fees
        if (this.hasFeeDetailsTarget) {
            if (this.promoAppliedValue) {
                this.feeDetailsTarget.classList.remove("hidden")
                if (this.hasFeeChevronTarget) this.feeChevronTarget.classList.add("rotate-180")
            }
        }
        if (this.hasFeeChevronTarget) {
            this.feeChevronTarget.classList.toggle("hidden", this.promoAppliedValue)
        }
        // Update Stripe fee label based on waived status
        if (this.hasStripeFeeLabelTarget) {
            this.stripeFeeLabelTarget.textContent = this.promoAppliedValue
                ? "Stripe card processing (2.9% + 30\u00a2) \u2014 included in CocoScout fee"
                : "Stripe card processing (2.9% + 30\u00a2)"
        }

        // Early bird net (shown inline if early bird price is set)
        if (this.hasEarlyBirdInputTarget && this.hasEarlyBirdNetTarget) {
            const earlyBirdPrice = parseFloat(this.earlyBirdInputTarget.value) || 0
            if (earlyBirdPrice > 0) {
                const ebFee = earlyBirdPrice * (feePercent / 100)
                const ebNet = earlyBirdPrice - ebFee
                this.earlyBirdNetTarget.textContent = this.fmt(ebNet)
                this.earlyBirdNetTarget.closest("[data-early-bird-net-row]")?.classList.remove("hidden")
            } else {
                this.earlyBirdNetTarget.closest("[data-early-bird-net-row]")?.classList.add("hidden")
            }
        }
    }

    // Promo modal
    openPromoModal(e) {
        e.preventDefault()
        if (this.hasPromoModalTarget) {
            this.promoModalTarget.classList.remove("hidden")
            this.promoInputTarget?.focus()
        }
    }

    closePromoModal() {
        if (this.hasPromoModalTarget) {
            this.promoModalTarget.classList.add("hidden")
        }
    }

    async applyPromo(e) {
        e.preventDefault()
        await this.validatePromo()
        if (this.promoAppliedValue) {
            this.closePromoModal()
        }
    }

    async validatePromo() {
        const code = this.promoInputTarget.value.trim()
        if (!code) {
            this.clearPromo()
            return
        }

        if (!this.validateUrlValue) return

        try {
            const response = await fetch(this.validateUrlValue, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
                },
                body: JSON.stringify({ code: code })
            })
            const data = await response.json()

            if (data.valid) {
                this.promoAppliedValue = true
                this.promoStatusTarget.innerHTML = `<span class="text-green-600 text-sm font-medium">✓ ${this.escapeHtml(data.description || "Code applied!")}</span>`
                this.promoInputTarget.classList.remove("border-red-500", "ring-2", "ring-red-200")
                if (this.hasPromoHiddenTarget) this.promoHiddenTarget.value = code
                if (this.hasPromoLinkTarget) this.promoLinkTarget.classList.add("hidden")
                if (this.hasPromoAppliedBadgeTarget) {
                    this.promoAppliedBadgeTarget.classList.remove("hidden")
                    this.promoAppliedBadgeTarget.querySelector("[data-promo-code-text]").textContent = code
                }
            } else {
                this.promoAppliedValue = false
                this.promoStatusTarget.innerHTML = `<span class="text-red-600 text-sm font-medium">${this.escapeHtml(data.error || "Invalid code")}</span>`
                this.promoInputTarget.classList.add("border-red-500", "ring-2", "ring-red-200")
                this.shakeElement(this.promoInputTarget)
                this.promoInputTarget.select()
                if (this.hasPromoHiddenTarget) this.promoHiddenTarget.value = ""
            }
        } catch {
            this.promoAppliedValue = false
            this.promoStatusTarget.innerHTML = `<span class="text-red-600 text-sm font-medium">Could not validate code. Please try again.</span>`
            this.promoInputTarget.classList.add("border-red-500", "ring-2", "ring-red-200")
        }

        this.calculate()
    }

    removePromo(e) {
        e.preventDefault()
        this.clearPromo()
        if (this.hasPromoLinkTarget) this.promoLinkTarget.classList.remove("hidden")
        if (this.hasPromoAppliedBadgeTarget) this.promoAppliedBadgeTarget.classList.add("hidden")
        if (this.hasPromoInputTarget) this.promoInputTarget.value = ""
    }

    clearPromo() {
        this.promoAppliedValue = false
        if (this.hasPromoStatusTarget) this.promoStatusTarget.innerHTML = ""
        if (this.hasPromoHiddenTarget) this.promoHiddenTarget.value = ""
        this.calculate()
    }

    toggleFeeDetails(e) {
        e.preventDefault()
        if (this.hasFeeDetailsTarget) {
            this.feeDetailsTarget.classList.toggle("hidden")
        }
        if (this.hasFeeChevronTarget) {
            this.feeChevronTarget.classList.toggle("rotate-180")
        }
    }

    clearPromoError() {
        if (this.hasPromoInputTarget) {
            this.promoInputTarget.classList.remove("border-red-500", "ring-2", "ring-red-200")
        }
        if (this.hasPromoStatusTarget) {
            this.promoStatusTarget.innerHTML = ""
        }
    }

    promoKeydown(e) {
        if (e.key === "Enter") {
            e.preventDefault()
            this.applyPromo(e)
        }
    }

    shakeElement(el) {
        el.animate([
            { transform: "translateX(0)" },
            { transform: "translateX(-6px)" },
            { transform: "translateX(6px)" },
            { transform: "translateX(-4px)" },
            { transform: "translateX(4px)" },
            { transform: "translateX(0)" }
        ], { duration: 400, easing: "ease-in-out" })
    }

    promoAppliedValueChanged() {
        this.calculate()
    }

    fmt(n) {
        return "$" + n.toFixed(2)
    }

    escapeHtml(str) {
        const div = document.createElement("div")
        div.textContent = str
        return div.innerHTML
    }
}
