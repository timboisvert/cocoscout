import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["signupCheck", "signupText", "declineCheck", "declineText", "signupButton", "declineButton"]
    static values = { status: String }

    connect() {
        this.updateButtons()
    }

    submitSignup(event) {
        event.preventDefault()
        const form = event.currentTarget.closest('form')
        this.submitForm(form, 'signup')
    }

    submitDecline(event) {
        event.preventDefault()
        const form = event.currentTarget.closest('form')
        this.submitForm(form, 'decline')
    }

    submitForm(form, status) {
        const formData = new FormData(form)
        
        fetch(form.action, {
            method: 'POST',
            headers: {
                'X-CSRF-Token': document.querySelector('meta[name=csrf-token]').content,
                'Accept': 'application/json'
            },
            body: formData
        }).then(response => {
            if (response.ok) {
                this.statusValue = status
                this.updateButtons()
                this.showCheckForStatus(status)
            }
        })
    }

    showCheckForStatus(status) {
        // Get all check/text targets for the status (supports multiple targets for mobile/desktop)
        const checkTargets = status === 'signup' ? this.signupCheckTargets : this.declineCheckTargets
        const textTargets = status === 'signup' ? this.signupTextTargets : this.declineTextTargets

        checkTargets.forEach(el => el.classList.remove('hidden'))
        textTargets.forEach(el => el.classList.add('hidden'))

        // After 2 seconds, show text and hide check
        setTimeout(() => {
            checkTargets.forEach(el => el.classList.add('hidden'))
            textTargets.forEach(el => el.classList.remove('hidden'))
        }, 2000)
    }

    updateButtons() {
        const currentStatus = this.statusValue

        // Update signup button
        if (this.hasSignupButtonTarget) {
            if (currentStatus === 'signup') {
                this.signupButtonTarget.classList.add('bg-pink-500', 'text-white')
                this.signupButtonTarget.classList.remove('bg-white', 'text-gray-700', 'hover:bg-gray-50')
            } else {
                this.signupButtonTarget.classList.remove('bg-pink-500', 'text-white')
                this.signupButtonTarget.classList.add('bg-white', 'text-gray-700', 'hover:bg-gray-50')
            }
        }

        // Update decline button
        if (this.hasDeclineButtonTarget) {
            if (currentStatus === 'decline') {
                this.declineButtonTarget.classList.add('bg-pink-500', 'text-white')
                this.declineButtonTarget.classList.remove('bg-white', 'text-gray-700', 'hover:bg-gray-50')
            } else {
                this.declineButtonTarget.classList.remove('bg-pink-500', 'text-white')
                this.declineButtonTarget.classList.add('bg-white', 'text-gray-700', 'hover:bg-gray-50')
            }
        }
    }
}
