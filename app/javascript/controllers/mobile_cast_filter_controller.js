import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["filterButton", "member", "list"]

    connect() {
        // Apply initial filter based on first active button
        const activeButton = this.filterButtonTargets.find(btn =>
            btn.classList.contains('bg-pink-500')
        )
        if (activeButton) {
            this.currentFilter = activeButton.dataset.filter
        } else {
            this.currentFilter = "all"
        }
    }

    filter(event) {
        event.preventDefault()
        const button = event.currentTarget
        const filterValue = button.dataset.filter

        this.currentFilter = filterValue

        // Update button styles
        this.filterButtonTargets.forEach(btn => {
            if (btn === button) {
                btn.classList.remove('bg-white', 'text-gray-700', 'border-gray-200')
                btn.classList.add('bg-pink-500', 'text-white', 'border-pink-500')
            } else {
                btn.classList.remove('bg-pink-500', 'text-white', 'border-pink-500')
                btn.classList.add('bg-white', 'text-gray-700', 'border-gray-200')
            }
        })

        // Apply filter to members
        this.applyFilter()
    }

    applyFilter() {
        this.memberTargets.forEach(member => {
            let shouldShow = true

            switch (this.currentFilter) {
                case "available":
                    shouldShow = member.dataset.isAvailable === 'true'
                    break
                case "fully-available":
                    shouldShow = member.dataset.isFullyAvailable === 'true'
                    break
                case "partially-available":
                    shouldShow = member.dataset.isPartiallyAvailable === 'true'
                    break
                case "all":
                default:
                    shouldShow = true
                    break
            }

            member.style.display = shouldShow ? '' : 'none'
        })
    }
}
