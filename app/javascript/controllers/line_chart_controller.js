import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["canvas"]
    static values = {
        data: Object,
        color: { type: String, default: "#ec4899" },
        label: { type: String, default: "Count" }
    }

    async connect() {
        this.chart = null
        // Dynamically import Chart.js only when this controller is used
        const { Chart } = await import("chart.js")
        this.Chart = Chart
        this.draw()
    }

    disconnect() {
        if (this.chart) {
            this.chart.destroy()
        }
    }

    draw() {
        const canvas = this.canvasTarget
        const data = this.dataValue
        const entries = Object.entries(data).sort((a, b) => a[0].localeCompare(b[0]))

        if (entries.length === 0) {
            return
        }

        const labels = entries.map(([date]) => this.formatLabel(date))
        const values = entries.map(([, value]) => value)

        // Destroy existing chart if it exists
        if (this.chart) {
            this.chart.destroy()
        }

        const ctx = canvas.getContext("2d")

        this.chart = new this.Chart(ctx, {
            type: "line",
            data: {
                labels: labels,
                datasets: [{
                    label: this.labelValue,
                    data: values,
                    borderColor: this.colorValue,
                    backgroundColor: this.colorValue + "20",
                    borderWidth: 2,
                    fill: true,
                    tension: 0.3,
                    pointRadius: 0,
                    pointHoverRadius: 6,
                    pointHoverBackgroundColor: this.colorValue,
                    pointHoverBorderColor: "#fff",
                    pointHoverBorderWidth: 2
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                interaction: {
                    mode: "index",
                    intersect: false
                },
                plugins: {
                    legend: {
                        display: false
                    },
                    tooltip: {
                        backgroundColor: "rgba(0, 0, 0, 0.8)",
                        titleColor: "#fff",
                        bodyColor: "#fff",
                        padding: 12,
                        displayColors: false,
                        callbacks: {
                            title: (items) => {
                                if (items.length > 0) {
                                    const idx = items[0].dataIndex
                                    return entries[idx][0]
                                }
                                return ""
                            },
                            label: (context) => {
                                return `${context.parsed.y} ${this.labelValue.toLowerCase()}`
                            }
                        }
                    }
                },
                scales: {
                    x: {
                        grid: {
                            display: false
                        },
                        ticks: {
                            maxRotation: 0,
                            autoSkip: true,
                            maxTicksLimit: 8,
                            color: "#9ca3af",
                            font: {
                                size: 11
                            }
                        }
                    },
                    y: {
                        beginAtZero: true,
                        grid: {
                            color: "#e5e7eb"
                        },
                        ticks: {
                            precision: 0,
                            color: "#9ca3af",
                            font: {
                                size: 11
                            }
                        }
                    }
                }
            }
        })
    }

    formatLabel(dateStr) {
        const date = new Date(dateStr + "T00:00:00")
        // Format as "Jan 15" or similar
        return date.toLocaleDateString("en-US", { month: "short", day: "numeric" })
    }

    // Allow external updates to the data
    dataValueChanged() {
        if (this.chart) {
            this.draw()
        }
    }
}
