import { Controller } from "@hotwired/stimulus"

// Simple bar chart using canvas API - no external dependencies
export default class extends Controller {
    static targets = ["canvas"]
    static values = {
        data: Object,
        color: { type: String, default: "#ec4899" },
        format: { type: String, default: "day" } // day, week, month
    }

    connect() {
        this.draw()
        // Redraw on resize
        this.resizeObserver = new ResizeObserver(() => this.draw())
        this.resizeObserver.observe(this.element)
    }

    disconnect() {
        if (this.resizeObserver) {
            this.resizeObserver.disconnect()
        }
    }

    draw() {
        const canvas = this.canvasTarget
        const ctx = canvas.getContext("2d")
        const data = this.dataValue
        const entries = Object.entries(data).sort((a, b) => a[0].localeCompare(b[0]))

        if (entries.length === 0) {
            return
        }

        // Set canvas size to match container
        const rect = this.element.getBoundingClientRect()
        const dpr = window.devicePixelRatio || 1
        canvas.width = rect.width * dpr
        canvas.height = rect.height * dpr
        canvas.style.width = `${rect.width}px`
        canvas.style.height = `${rect.height}px`
        ctx.scale(dpr, dpr)

        const width = rect.width
        const height = rect.height
        const padding = { top: 20, right: 20, bottom: 40, left: 50 }
        const chartWidth = width - padding.left - padding.right
        const chartHeight = height - padding.top - padding.bottom

        // Clear canvas
        ctx.clearRect(0, 0, width, height)

        // Find max value
        const values = entries.map(e => e[1])
        const maxValue = Math.max(...values, 1)

        // Calculate bar width
        const barWidth = Math.max(2, (chartWidth / entries.length) - 2)
        const barGap = 2

        // Draw grid lines
        ctx.strokeStyle = "#e5e7eb"
        ctx.lineWidth = 1
        const gridLines = 4
        for (let i = 0; i <= gridLines; i++) {
            const y = padding.top + (chartHeight / gridLines) * i
            ctx.beginPath()
            ctx.moveTo(padding.left, y)
            ctx.lineTo(width - padding.right, y)
            ctx.stroke()

            // Y-axis labels
            const labelValue = Math.round(maxValue - (maxValue / gridLines) * i)
            ctx.fillStyle = "#9ca3af"
            ctx.font = "11px system-ui"
            ctx.textAlign = "right"
            ctx.fillText(labelValue.toString(), padding.left - 8, y + 4)
        }

        // Draw bars
        ctx.fillStyle = this.colorValue
        entries.forEach((entry, i) => {
            const [, value] = entry
            const barHeight = (value / maxValue) * chartHeight
            const x = padding.left + i * (barWidth + barGap)
            const y = padding.top + chartHeight - barHeight

            // Draw bar with rounded top
            const radius = Math.min(3, barWidth / 2)
            ctx.beginPath()
            ctx.moveTo(x + radius, y)
            ctx.lineTo(x + barWidth - radius, y)
            ctx.quadraticCurveTo(x + barWidth, y, x + barWidth, y + radius)
            ctx.lineTo(x + barWidth, y + barHeight)
            ctx.lineTo(x, y + barHeight)
            ctx.lineTo(x, y + radius)
            ctx.quadraticCurveTo(x, y, x + radius, y)
            ctx.fill()
        })

        // Draw x-axis labels (show every Nth label based on data density)
        ctx.fillStyle = "#6b7280"
        ctx.font = "10px system-ui"
        ctx.textAlign = "center"

        const labelInterval = Math.max(1, Math.floor(entries.length / 8))
        entries.forEach((entry, i) => {
            if (i % labelInterval !== 0 && i !== entries.length - 1) return

            const [key] = entry
            const x = padding.left + i * (barWidth + barGap) + barWidth / 2
            const y = height - padding.bottom + 15

            let label = key
            if (this.formatValue === "day") {
                // Format as "Jan 5"
                const date = new Date(key)
                label = date.toLocaleDateString("en-US", { month: "short", day: "numeric" })
            } else if (this.formatValue === "week") {
                // Format as "W1", "W2", etc. or date
                const date = new Date(key)
                label = date.toLocaleDateString("en-US", { month: "short", day: "numeric" })
            } else if (this.formatValue === "month") {
                // Format as "Jan", "Feb", etc.
                const date = new Date(key)
                label = date.toLocaleDateString("en-US", { month: "short" })
            }

            ctx.fillText(label, x, y)
        })

        // Draw summary at top right
        const total = values.reduce((a, b) => a + b, 0)
        const avg = (total / entries.length).toFixed(1)
        ctx.fillStyle = "#374151"
        ctx.font = "11px system-ui"
        ctx.textAlign = "right"
        ctx.fillText(`Total: ${total} · Avg: ${avg}/period`, width - padding.right, 12)
    }
}
