import { Controller } from "@hotwired/stimulus"

// Handles individual zone card behavior
// - Shows/hides input fields based on zone type selection
// - Calculates zone capacity
export default class extends Controller {
    static targets = [
        "zoneType",
        "destroy",
        "capacity",
        "name",
        // Individual seats
        "individualSeatsInputs",
        "unitCount",
        "capacityPerUnit",
        // Tables
        "tablesInputs",
        "unitCountTables",
        "capacityPerUnitTables",
        // Rows
        "rowsInputs",
        "unitCountRows",
        "capacityPerUnitRows",
        // Booths
        "boothsInputs",
        "unitCountBooths",
        "capacityPerUnitBooths",
        // Standing
        "standingInputs",
        "unitCountStanding",
        "capacityPerUnitStanding"
    ]

    connect() {
        this.updateInputs()
        this.calculateCapacity()
    }

    updateInputs() {
        const selectedType = this.getSelectedZoneType()

        // Hide all input sections
        this.hideAllInputs()

        // Show the relevant input section
        switch (selectedType) {
            case "individual_seats":
                if (this.hasIndividualSeatsInputsTarget) {
                    this.individualSeatsInputsTarget.classList.remove("hidden")
                }
                break
            case "tables":
                if (this.hasTablesInputsTarget) {
                    this.tablesInputsTarget.classList.remove("hidden")
                }
                break
            case "rows":
                if (this.hasRowsInputsTarget) {
                    this.rowsInputsTarget.classList.remove("hidden")
                }
                break
            case "booths":
                if (this.hasBoothsInputsTarget) {
                    this.boothsInputsTarget.classList.remove("hidden")
                }
                break
            case "standing":
                if (this.hasStandingInputsTarget) {
                    this.standingInputsTarget.classList.remove("hidden")
                }
                break
        }

        this.calculateCapacity()
    }

    hideAllInputs() {
        const inputTargets = [
            "individualSeatsInputsTarget",
            "tablesInputsTarget",
            "rowsInputsTarget",
            "boothsInputsTarget",
            "standingInputsTarget"
        ]

        inputTargets.forEach(target => {
            const hasMethod = `has${target.charAt(0).toUpperCase()}${target.slice(1)}`
            if (this[hasMethod] && this[target]) {
                this[target].classList.add("hidden")
            }
        })
    }

    calculateCapacity() {
        const selectedType = this.getSelectedZoneType()
        let unitCount = 1
        let capacityPerUnit = 1

        switch (selectedType) {
            case "individual_seats":
                unitCount = this.getInputValue("unitCount", 1)
                capacityPerUnit = 1
                break
            case "tables":
                unitCount = this.getInputValue("unitCountTables", 1)
                capacityPerUnit = this.getInputValue("capacityPerUnitTables", 2)
                break
            case "rows":
                unitCount = this.getInputValue("unitCountRows", 1)
                capacityPerUnit = this.getInputValue("capacityPerUnitRows", 10)
                break
            case "booths":
                unitCount = this.getInputValue("unitCountBooths", 1)
                capacityPerUnit = this.getInputValue("capacityPerUnitBooths", 4)
                break
            case "standing":
                unitCount = this.getInputValue("unitCountStanding", 50)
                capacityPerUnit = 1
                break
        }

        const total = unitCount * capacityPerUnit

        if (this.hasCapacityTarget) {
            this.capacityTarget.textContent = total
        }

        // Update the hidden fields used for form submission
        this.updateHiddenFields(selectedType, unitCount, capacityPerUnit)
    }

    updateHiddenFields(zoneType, unitCount, capacityPerUnit) {
        // Find or create hidden fields for unit_count and capacity_per_unit
        const container = this.element
        const index = this.getZoneIndex()

        // Update or create unit_count hidden field
        let unitCountField = container.querySelector(`input[name="zones[${index}][unit_count]"]:not([name*="_"])`)
        if (!unitCountField) {
            unitCountField = document.createElement("input")
            unitCountField.type = "hidden"
            unitCountField.name = `zones[${index}][unit_count]`
            container.appendChild(unitCountField)
        }
        unitCountField.value = unitCount

        // Update or create capacity_per_unit hidden field
        let capacityField = container.querySelector(`input[name="zones[${index}][capacity_per_unit]"]:not([name*="_"])`)
        if (!capacityField) {
            capacityField = document.createElement("input")
            capacityField.type = "hidden"
            capacityField.name = `zones[${index}][capacity_per_unit]`
            container.appendChild(capacityField)
        }
        capacityField.value = capacityPerUnit
    }

    getZoneIndex() {
        // Extract index from the name field
        const nameField = this.element.querySelector("input[name*='[name]']")
        if (nameField) {
            const match = nameField.name.match(/zones\[(\d+|NEW_CHILD_RECORD)\]/)
            if (match) return match[1]
        }
        return "0"
    }

    getSelectedZoneType() {
        const checked = this.zoneTypeTargets.find(input => input.checked)
        return checked ? checked.value : "individual_seats"
    }

    getInputValue(targetName, defaultValue) {
        const hasMethod = `has${targetName.charAt(0).toUpperCase()}${targetName.slice(1)}Target`
        const targetMethod = `${targetName}Target`

        if (this[hasMethod] && this[targetMethod]) {
            return parseInt(this[targetMethod].value, 10) || defaultValue
        }
        return defaultValue
    }
}
