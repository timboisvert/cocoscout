import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    update(event) {
        const select = event.currentTarget
        const params = new URLSearchParams()

        const searchValue = select.dataset.filterSelectSearchValue
        const showValue = select.dataset.filterSelectShowValue
        const filterValue = select.dataset.filterSelectFilterValue
        const typeValue = select.dataset.filterSelectTypeValue

        if (searchValue) params.set("q", searchValue)
        if (showValue) params.set("show", showValue)

        if (select.name === "filter") {
            params.set("filter", select.value)
            if (typeValue) params.set("type", typeValue)
        } else if (select.name === "type") {
            params.set("type", select.value)
            if (filterValue) params.set("filter", filterValue)
        } else if (select.name === "sort") {
            params.set("sort", select.value)
            if (filterValue) params.set("filter", filterValue)
            if (typeValue) params.set("type", typeValue)
        }

        const baseUrl = select.closest("form")?.action || window.location.pathname
        window.location.href = baseUrl + "?" + params.toString()
    }
}
