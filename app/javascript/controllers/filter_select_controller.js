import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    update(event) {
        console.log("Filter select update triggered", event)
        const select = event.currentTarget
        console.log("Select element:", select)
        console.log("Select name:", select.name)
        console.log("Select value:", select.value)
        console.log("Dataset:", select.dataset)

        const params = new URLSearchParams()

        const searchValue = select.dataset.filterSelectSearchValue
        const showValue = select.dataset.filterSelectShowValue
        const filterValue = select.dataset.filterSelectFilterValue
        const typeValue = select.dataset.filterSelectTypeValue

        console.log("Data values:", { searchValue, showValue, filterValue, typeValue })

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
        const fullUrl = baseUrl + "?" + params.toString()
        console.log("Navigating to:", fullUrl)
        window.location.href = fullUrl
    }
}
