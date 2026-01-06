import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["input", "lengthCheck", "uppercaseCheck", "lowercaseCheck", "numberCheck", "specialCheck", "submit"]

    connect() {
        console.log("Password strength controller connected")
        console.log("Submit target found:", this.hasSubmitTarget)
        this.checkStrength()
    }

    checkStrength() {
        const password = this.inputTarget.value
        console.log("Checking password:", password)

        // Check each requirement
        const lengthMet = password.length >= 8
        const uppercaseMet = /[A-Z]/.test(password)
        const lowercaseMet = /[a-z]/.test(password)
        const numberMet = /[0-9]/.test(password)
        const specialMet = /[^A-Za-z0-9]/.test(password)

        console.log("Requirements:", { lengthMet, uppercaseMet, lowercaseMet, numberMet, specialMet })

        // Update each requirement indicator
        this.updateRequirement(this.lengthCheckTarget, lengthMet)
        this.updateRequirement(this.uppercaseCheckTarget, uppercaseMet)
        this.updateRequirement(this.lowercaseCheckTarget, lowercaseMet)
        this.updateRequirement(this.numberCheckTarget, numberMet)
        this.updateRequirement(this.specialCheckTarget, specialMet)

        // Enable/disable submit button based on all requirements
        const allMet = lengthMet && uppercaseMet && lowercaseMet && numberMet && specialMet
        console.log("All met:", allMet)

        if (this.hasSubmitTarget) {
            if (allMet) {
                console.log("Enabling button")
                this.enableButton()
            } else {
                console.log("Disabling button")
                this.disableButton()
            }
        }
    }

    enableButton() {
        this.submitTarget.removeAttribute('disabled')
        this.submitTarget.classList.remove('!opacity-50', '!cursor-not-allowed', 'opacity-50', 'cursor-not-allowed')
        this.submitTarget.classList.add('enabled')
    }

    disableButton() {
        this.submitTarget.setAttribute('disabled', 'disabled')
        this.submitTarget.classList.remove('enabled')
        this.submitTarget.classList.add('!opacity-50', '!cursor-not-allowed')
    }

    updateRequirement(element, isMet) {
        const icon = element.querySelector('svg')
        const text = element.querySelector('span')

        if (isMet) {
            // Met requirement - show pink checkmark
            icon.classList.remove('text-slate-400')
            icon.classList.add('text-pink-500')
            text.classList.remove('text-slate-600')
            text.classList.add('text-slate-900', 'font-medium')
            icon.innerHTML = `
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
      `
        } else {
            // Unmet requirement - show gray circle
            icon.classList.remove('text-pink-500')
            icon.classList.add('text-slate-400')
            text.classList.remove('text-slate-900', 'font-medium')
            text.classList.add('text-slate-600')
            icon.innerHTML = `
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" opacity="0.3" />
      `
        }
    }
}
