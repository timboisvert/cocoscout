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
        const talentPoolIdValue = select.dataset.filterSelectTalentPoolIdValue

        console.log("Data values:", { searchValue, showValue, filterValue, typeValue, talentPoolIdValue })

        if (searchValue) params.set("q", searchValue)
        if (showValue) params.set("show", showValue)

        if (select.name === "filter") {
            params.set("filter", select.value)
            if (typeValue) params.set("type", typeValue)
            // Don't carry over talent_pool_id when changing filter
        } else if (select.name === "talent_pool_id") {
            params.set("talent_pool_id", select.value)
            if (filterValue) params.set("filter", filterValue)
            if (typeValue) params.set("type", typeValue)
        } else if (select.name === "type") {
            params.set("type", select.value)
            if (filterValue) params.set("filter", filterValue)
            if (talentPoolIdValue) params.set("talent_pool_id", talentPoolIdValue)
        } else if (select.name === "sort") {
            params.set("sort", select.value)
            if (filterValue) params.set("filter", filterValue)
            if (typeValue) params.set("type", typeValue)
            if (talentPoolIdValue) params.set("talent_pool_id", talentPoolIdValue)
        }

        const baseUrl = select.closest("form")?.action || window.location.pathname
        const fullUrl = baseUrl + "?" + params.toString()
        console.log("Navigating to:", fullUrl)
        window.location.href = fullUrl
    }
}
