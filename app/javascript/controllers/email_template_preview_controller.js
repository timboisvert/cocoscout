import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["variableInput", "subjectPreview", "bodyPreview", "subjectRaw", "bodyRaw"]
    static values = {
        subjectTemplate: String,
        bodyTemplate: String,
        emailLayoutPrefix: { type: String, default: "" },
        emailLayoutSuffix: { type: String, default: "" }
    }

    connect() {
        this.updatePreview()
    }

    updatePreview() {
        const variables = this.collectVariables()

        // Update subject preview
        if (this.hasSubjectPreviewTarget) {
            this.subjectPreviewTarget.textContent = this.interpolateText(this.subjectTemplateValue, variables)
        }

        // Update iframe with styled body
        const iframe = document.getElementById('email-preview-frame')
        if (iframe) {
            const interpolatedBody = this.interpolateHtml(this.bodyTemplateValue, variables)
            // Get the current iframe content and update just the body portion
            const currentDoc = iframe.contentDocument || iframe.contentWindow.document
            const emailContainer = currentDoc.querySelector('.email-container')
            if (emailContainer) {
                emailContainer.innerHTML = interpolatedBody
            }
        }

        // Update raw subject
        if (this.hasSubjectRawTarget) {
            this.subjectRawTarget.textContent = this.subjectTemplateValue
        }

        // Update raw body
        if (this.hasBodyRawTarget) {
            this.bodyRawTarget.textContent = this.bodyTemplateValue
        }
    }

    collectVariables() {
        const variables = {}
        this.variableInputTargets.forEach(input => {
            const name = input.dataset.variableName
            variables[name] = input.value
        })
        return variables
    }

    interpolateText(template, variables) {
        if (!template) return ""

        let result = template

        // First handle conditional blocks: {{#var}}content{{/var}}
        Object.entries(variables).forEach(([key, value]) => {
            const conditionalRegex = new RegExp(`\\{\\{#${this.escapeRegex(key)}\\}\\}([\\s\\S]*?)\\{\\{\\/${this.escapeRegex(key)}\\}\\}`, 'g')
            result = result.replace(conditionalRegex, (match, content) => {
                return value && value.trim() ? content : ''
            })
        })

        // Remove any remaining conditional blocks for variables not provided
        result = result.replace(/\{\{#\w+\}\}[\s\S]*?\{\{\/\w+\}\}/g, '')

        // Then handle simple variable substitution
        Object.entries(variables).forEach(([key, value]) => {
            const regex = new RegExp(`\\{\\{\\s*${this.escapeRegex(key)}\\s*\\}\\}`, 'g')
            result = result.replace(regex, value)
        })
        return result
    }

    interpolateHtml(template, variables) {
        if (!template) return ""

        let result = template

        // First handle conditional blocks: {{#var}}content{{/var}}
        Object.entries(variables).forEach(([key, value]) => {
            const conditionalRegex = new RegExp(`\\{\\{#${this.escapeRegex(key)}\\}\\}([\\s\\S]*?)\\{\\{\\/${this.escapeRegex(key)}\\}\\}`, 'g')
            result = result.replace(conditionalRegex, (match, content) => {
                return value && value.trim() ? content : ''
            })
        })

        // Remove any remaining conditional blocks for variables not provided
        result = result.replace(/\{\{#\w+\}\}[\s\S]*?\{\{\/\w+\}\}/g, '')

        // Then handle simple variable substitution
        Object.entries(variables).forEach(([key, value]) => {
            const regex = new RegExp(`\\{\\{\\s*${this.escapeRegex(key)}\\s*\\}\\}`, 'g')
            // For HTML body, preserve HTML content for body_content/custom_message type vars
            if (key.match(/content|message|body/i) && value.includes('<')) {
                result = result.replace(regex, value)
            } else {
                result = result.replace(regex, this.escapeHtml(value))
            }
        })
        return result
    }

    escapeRegex(str) {
        return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    }

    escapeHtml(str) {
        const div = document.createElement('div')
        div.textContent = str
        return div.innerHTML
    }

    resetVariables(event) {
        event.preventDefault()
        this.variableInputTargets.forEach(input => {
            input.value = input.dataset.defaultValue || ""
        })
        this.updatePreview()
    }
}
