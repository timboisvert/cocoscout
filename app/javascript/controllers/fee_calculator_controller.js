import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="fee-calculator"
export default class extends Controller {
    static targets = [
        "priceInput", "earlyBirdInput",
        "breakdown", "breakdownPlaceholder", "earlyBirdSection",
        "promoInput", "promoStatus", "promoHidden", "promoCoverageHidden",
        "promoModal", "promoLink", "promoAppliedBadge",
        "feeRow", "feeLabel", "feeDetails", "feeChevron",
        "registrationPrice", "cocoscoutFee", "producerNet", "stripeFee", "stripeFeeLabel", "platformFee",
        "earlyBirdNet", "feeExplanation"
    ]

    static values = {
        validateUrl: String,
        cocoscoutFeePercent: { type: Number, default: 5.0 },
        stripeFeePercent: { type: Number, default: 2.9 },
        stripeFeeCents: { type: Number, default: 30 },
        promoApplied: { type: Boolean, default: false },
        promoCoverageType: { type: String, default: "none" }
    }

    connect() {
        // Restore coverage type from hidden field if promo is already applied
        if (this.promoAppliedValue && this.hasPromoCoverageHiddenTarget) {
            const storedType = this.promoCoverageHiddenTarget.value
            if (storedType && storedType !== "none") {
                this.promoCoverageTypeValue = storedType
            } else {
                this.promoCoverageTypeValue = "full"
            }
        }
        this.calculate()
    }

    calculate() {
        const price = this.hasPriceInputTarget ? (parseFloat(this.priceInputTarget.value) || 0) : 0

        if (price <= 0) {
            if (this.hasBreakdownTarget) this.breakdownTarget.classList.add("hidden")
            if (this.hasBreakdownPlaceholderTarget) this.breakdownPlaceholderTarget.classList.remove("hidden")
            if (this.hasEarlyBirdSectionTarget) this.earlyBirdSectionTarget.classList.add("hidden")
            return
        }

        if (this.hasBreakdownTarget) this.breakdownTarget.classList.remove("hidden")
        if (this.hasBreakdownPlaceholderTarget) this.breakdownPlaceholderTarget.classList.add("hidden")
        if (this.hasEarlyBirdSectionTarget) this.earlyBirdSectionTarget.classList.remove("hidden")

        const coverageType = this.promoCoverageTypeValue // "none", "full", or "platform_only"
        let cocoscoutFee, producerNet, stripeFee, platformFee

        if (coverageType === "full") {
            // All fees waived — producer keeps 100%
            cocoscoutFee = 0
            producerNet = price
            stripeFee = price * (this.stripeFeePercentValue / 100) + (this.stripeFeeCentsValue / 100)
            platformFee = 0
        } else if (coverageType === "platform_only") {
            // Platform fee waived, but Stripe processing fee still applies to producer
            stripeFee = price * (this.stripeFeePercentValue / 100) + (this.stripeFeeCentsValue / 100)
            cocoscoutFee = stripeFee // Only Stripe fees, shown as total fee
            producerNet = price - stripeFee
            platformFee = 0
        } else {
            // No promo - standard 5% fee
            cocoscoutFee = price * (this.cocoscoutFeePercentValue / 100)
            producerNet = price - cocoscoutFee
            stripeFee = price * (this.stripeFeePercentValue / 100) + (this.stripeFeeCentsValue / 100)
            platformFee = Math.max(cocoscoutFee - stripeFee, 0)
        }

        if (this.hasRegistrationPriceTarget) this.registrationPriceTarget.textContent = this.fmt(price)
        if (this.hasCocoscoutFeeTarget) this.cocoscoutFeeTarget.textContent = this.fmt(cocoscoutFee)
        if (this.hasFeeLabelTarget) {
            if (coverageType === "full") {
                this.feeLabelTarget.textContent = "CocoScout fee (waived — all fees covered)"
            } else if (coverageType === "platform_only") {
                this.feeLabelTarget.textContent = "Stripe processing fee (2.9% + 30¢)"
            } else {
                this.feeLabelTarget.textContent = `CocoScout fee (${this.cocoscoutFeePercentValue}% — includes processing fees)`
            }
        }
        if (this.hasProducerNetTarget) this.producerNetTarget.textContent = this.fmt(producerNet)
        if (this.hasStripeFeeTarget) this.stripeFeeTarget.textContent = this.fmt(stripeFee)
        if (this.hasPlatformFeeTarget) this.platformFeeTarget.textContent = this.fmt(platformFee)

        // Style fee row based on promo
        if (this.hasFeeRowTarget) {
            this.feeRowTarget.classList.toggle("text-green-600", coverageType !== "none")
            this.feeRowTarget.classList.toggle("text-gray-600", coverageType === "none")
        }
        // When fee is waived, auto-expand details to show what's covered
        if (this.hasFeeDetailsTarget) {
            if (coverageType !== "none") {
                this.feeDetailsTarget.classList.remove("hidden")
                if (this.hasFeeChevronTarget) this.feeChevronTarget.classList.add("rotate-180")
            }
        }
        if (this.hasFeeChevronTarget) {
            this.feeChevronTarget.classList.toggle("hidden", coverageType !== "none")
        }
        // Update Stripe fee label based on coverage
        if (this.hasStripeFeeLabelTarget) {
            if (coverageType === "full") {
                this.stripeFeeLabelTarget.textContent = "Stripe card processing (2.9% + 30\u00a2) \u2014 covered by promo"
            } else if (coverageType === "platform_only") {
                this.stripeFeeLabelTarget.textContent = "Stripe card processing (2.9% + 30\u00a2) \u2014 paid by you"
            } else {
                this.stripeFeeLabelTarget.textContent = "Stripe card processing (2.9% + 30\u00a2)"
            }
        }
        // Update fee explanation based on coverage
        if (this.hasFeeExplanationTarget) {
            if (coverageType === "full") {
                this.feeExplanationTarget.textContent = "Your promo code covers both the CocoScout fee and Stripe processing fees. You keep 100% of each registration."
            } else if (coverageType === "platform_only") {
                this.feeExplanationTarget.textContent = "Your promo code covers the CocoScout platform fee. Stripe processing fees (2.9% + 30\u00a2) still apply and are deducted from your revenue."
            } else {
                this.feeExplanationTarget.textContent = "Stripe fees are the standard rate for online card payments. CocoScout covers these out of the 5% fee \u2014 net revenue will always be exactly 95%."
            }
        }

        // Early bird net (shown inline if early bird price is set)
        if (this.hasEarlyBirdInputTarget && this.hasEarlyBirdNetTarget) {
            const earlyBirdPrice = parseFloat(this.earlyBirdInputTarget.value) || 0
            if (earlyBirdPrice > 0) {
                let ebNet
                if (coverageType === "full") {
                    ebNet = earlyBirdPrice
                } else if (coverageType === "platform_only") {
                    const ebStripe = earlyBirdPrice * (this.stripeFeePercentValue / 100) + (this.stripeFeeCentsValue / 100)
                    ebNet = earlyBirdPrice - ebStripe
                } else {
                    const ebFee = earlyBirdPrice * (this.cocoscoutFeePercentValue / 100)
                    ebNet = earlyBirdPrice - ebFee
                }
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
                this.promoCoverageTypeValue = data.coverage_type || "full"
                this.promoStatusTarget.innerHTML = `<span class="text-green-600 text-sm font-medium">✓ ${this.escapeHtml(data.description || "Code applied!")}</span>`
                this.promoInputTarget.classList.remove("border-red-500", "ring-2", "ring-red-200")
                if (this.hasPromoHiddenTarget) this.promoHiddenTarget.value = code
                if (this.hasPromoCoverageHiddenTarget) this.promoCoverageHiddenTarget.value = data.coverage_type || "full"
                if (this.hasPromoLinkTarget) this.promoLinkTarget.classList.add("hidden")
                if (this.hasPromoAppliedBadgeTarget) {
                    this.promoAppliedBadgeTarget.classList.remove("hidden")
                    this.promoAppliedBadgeTarget.querySelector("[data-promo-code-text]").textContent = code
                }
            } else {
                this.promoAppliedValue = false
                this.promoCoverageTypeValue = "none"
                this.promoStatusTarget.innerHTML = `<span class="text-red-600 text-sm font-medium">${this.escapeHtml(data.error || "Invalid code")}</span>`
                this.promoInputTarget.classList.add("border-red-500", "ring-2", "ring-red-200")
                this.shakeElement(this.promoInputTarget)
                this.promoInputTarget.select()
                if (this.hasPromoHiddenTarget) this.promoHiddenTarget.value = ""
            }
        } catch {
            this.promoAppliedValue = false
            this.promoCoverageTypeValue = "none"
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
        this.promoCoverageTypeValue = "none"
        if (this.hasPromoStatusTarget) this.promoStatusTarget.innerHTML = ""
        if (this.hasPromoHiddenTarget) this.promoHiddenTarget.value = ""
        if (this.hasPromoCoverageHiddenTarget) this.promoCoverageHiddenTarget.value = "none"
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
