import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    update(event) {
        const select = event.currentTarget
        const params = new URLSearchParams()

        const searchValue = select.dataset.filterSelectSearchValue
        const showValue = select.dataset.filterSelectShowValue
        const filterValue = select.dataset.filterSelectFilterValue
        const typeValue = select.dataset.filterSelectTypeValue
        const talentPoolIdValue = select.dataset.filterSelectTalentPoolIdValue
        const qValue = select.dataset.filterSelectQValue
        const productionIdValue = select.dataset.filterSelectProductionIdValue
        const orderValue = select.dataset.filterSelectOrderValue
        const eventTypeValue = select.dataset.filterSelectEventTypeValue
        const paramValue = select.dataset.filterSelectParamValue

        if (searchValue) params.set("q", searchValue)
        if (qValue) params.set("q", qValue)
        if (showValue) params.set("show", showValue)

        // Generic param handling - allows any param name to be updated
        if (paramValue) {
            if (select.value) params.set(paramValue, select.value)
            if (filterValue) params.set("filter", filterValue)
            if (eventTypeValue) params.set("event_type", eventTypeValue)
        } else if (select.name === "filter") {
            params.set("filter", select.value)
            if (typeValue) params.set("type", typeValue)
            if (productionIdValue) params.set("production_id", productionIdValue)
            if (orderValue) params.set("order", orderValue)
        } else if (select.name === "talent_pool_id") {
            params.set("talent_pool_id", select.value)
            if (filterValue) params.set("filter", filterValue)
            if (typeValue) params.set("type", typeValue)
        } else if (select.name === "production_id") {
            if (select.value) params.set("production_id", select.value)
            if (filterValue) params.set("filter", filterValue)
            if (orderValue) params.set("order", orderValue)
        } else if (select.name === "order") {
            params.set("order", select.value)
            if (filterValue) params.set("filter", filterValue)
            if (productionIdValue) params.set("production_id", productionIdValue)
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
        window.location.href = fullUrl
    }
}
