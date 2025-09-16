import { Controller } from "@hotwired/stimulus"

// Usage: data-controller="tooltip" data-tooltip-text="Your tooltip text here"
export default class extends Controller {
    static values = { text: String }

    connect() {
        this._createTooltipElement()
        this.element.addEventListener('mouseenter', this._showTooltip)
        this.element.addEventListener('mouseleave', this._hideTooltip)
    }

    disconnect() {
        this._removeTooltipElement()
        this.element.removeEventListener('mouseenter', this._showTooltip)
        this.element.removeEventListener('mouseleave', this._hideTooltip)
    }

    _createTooltipElement = () => {
        this.tooltip = document.createElement('div')
        this.tooltip.className = 'stimulus-tooltip hidden pointer-events-none px-2 py-1 rounded bg-pink-500 text-white text-xs absolute z-50 shadow-lg transition-opacity duration-150'
        this.tooltip.style.position = 'absolute'
        this.tooltip.style.whiteSpace = 'nowrap'
        this.tooltip.innerText = this.textValue || this.element.dataset.tooltipText || ''

        // Add triangle
        this.triangle = document.createElement('div')
        this.triangle.className = 'stimulus-tooltip-triangle'
        Object.assign(this.triangle.style, {
            position: 'absolute',
            left: '50%',
            top: '100%',
            transform: 'translateX(-50%)',
            width: '0',
            height: '0',
            borderLeft: '7px solid transparent',
            borderRight: '7px solid transparent',
            borderTop: '7px solid #ec4899', // Tailwind pink-500
        })
        this.tooltip.appendChild(this.triangle)
        document.body.appendChild(this.tooltip)
    }

    _showTooltip = (event) => {
        // Only update text node, not triangle
        this.tooltip.childNodes[0].nodeValue = this.textValue || this.element.dataset.tooltipText || ''
        this.tooltip.classList.remove('hidden')
        const rect = this.element.getBoundingClientRect()
        const tooltipRect = this.tooltip.getBoundingClientRect()
        const top = window.scrollY + rect.top - tooltipRect.height - 8
        const left = window.scrollX + rect.left + (rect.width - tooltipRect.width) / 2
        this.tooltip.style.top = `${top}px`
        this.tooltip.style.left = `${left}px`
        this.tooltip.style.opacity = '1'
    }

    _hideTooltip = () => {
        this.tooltip.classList.add('hidden')
        this.tooltip.style.opacity = '0'
    }

    _removeTooltipElement = () => {
        if (this.tooltip && this.tooltip.parentNode) {
            this.tooltip.parentNode.removeChild(this.tooltip)
        }
        this.triangle = null
    }
}
