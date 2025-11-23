import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["categoryButton", "categoryPanel"]

    selectCategory(event) {
        const button = event.currentTarget
        const category = button.dataset.category

        // Update button states
        this.categoryButtonTargets.forEach(btn => {
            if (btn.dataset.category === category) {
                btn.classList.remove('text-gray-700', 'hover:bg-gray-50')
                btn.classList.add('bg-pink-50', 'text-pink-700')
            } else {
                btn.classList.remove('bg-pink-50', 'text-pink-700')
                btn.classList.add('text-gray-700', 'hover:bg-gray-50')
            }
        })

        // Show selected category panel
        this.categoryPanelTargets.forEach(panel => {
            if (panel.dataset.category === category) {
                panel.classList.remove('hidden')
            } else {
                panel.classList.add('hidden')
            }
        })
    }

    updateBadge(event) {
        const checkbox = event.target
        const category = checkbox.dataset.skillCategory

        // Find the category button
        const categoryButton = this.categoryButtonTargets.find(btn => btn.dataset.category === category)
        if (!categoryButton) return

        // Count selected skills in this category
        const categoryPanel = this.categoryPanelTargets.find(panel => panel.dataset.category === category)
        if (!categoryPanel) return

        const checkedCount = categoryPanel.querySelectorAll('.skill-checkbox:checked').length

        // Update or create badge
        let badge = categoryButton.querySelector('.bg-pink-500')

        if (checkedCount > 0) {
            if (!badge) {
                badge = document.createElement('span')
                badge.className = 'px-2 py-0.5 text-xs font-medium bg-pink-500 text-white rounded-full'
                categoryButton.appendChild(badge)
            }
            badge.textContent = checkedCount
        } else {
            if (badge) {
                badge.remove()
            }
        }
    }
}
