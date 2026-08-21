import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "canvas"]
    static values = {
        url: String,
        size: { type: Number, default: 280 },
        filename: { type: String, default: "cocoscout-qr-code.png" }
    }

    async connect() {
        // Load QRCode library dynamically if not already loaded
        await this.loadQRCodeLibrary()
        // Without a modal target the canvas is always visible, so render now
        if (!this.hasModalTarget && this.hasCanvasTarget) {
            this.generateQRCode()
        }
    }

    loadQRCodeLibrary() {
        if (window.qrcode) return Promise.resolve()

        return new Promise((resolve, reject) => {
            const script = document.createElement('script')
            script.src = 'https://cdn.jsdelivr.net/npm/qrcode-generator@1.4.4/qrcode.min.js'
            script.onload = () => resolve()
            script.onerror = () => reject(new Error('Failed to load QRCode library'))
            document.head.appendChild(script)
        })
    }

    async open() {
        this.modalTarget.classList.remove('hidden')
        document.body.classList.add('overflow-hidden')

        // Ensure library is loaded before generating
        await this.loadQRCodeLibrary()
        this.generateQRCode()
    }

    close() {
        this.modalTarget.classList.add('hidden')
        document.body.classList.remove('overflow-hidden')
    }

    closeOnEscape(event) {
        if (event.key === 'Escape') {
            this.close()
        }
    }

    closeOnBackdrop(event) {
        if (event.target === this.modalTarget) {
            this.close()
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    generateQRCode() {
        const canvas = this.canvasTarget
        const url = this.urlValue
        const size = this.sizeValue

        if (typeof qrcode === 'undefined') {
            console.error('QRCode library not loaded')
            return
        }

        try {
            // Generate QR code using qrcode-generator
            // Type 0 = auto-detect, Error correction M = medium (15%)
            const qr = qrcode(0, 'M')
            qr.addData(url)
            qr.make()

            const moduleCount = qr.getModuleCount()
            const cellSize = size / moduleCount

            canvas.width = size
            canvas.height = size

            const ctx = canvas.getContext('2d')

            // Fill background
            ctx.fillStyle = '#ffffff'
            ctx.fillRect(0, 0, size, size)

            // Draw QR code modules
            ctx.fillStyle = '#000000'
            for (let row = 0; row < moduleCount; row++) {
                for (let col = 0; col < moduleCount; col++) {
                    if (qr.isDark(row, col)) {
                        ctx.fillRect(col * cellSize, row * cellSize, cellSize, cellSize)
                    }
                }
            }

        } catch (error) {
            console.error('QR Code generation failed:', error)
        }
    }

    download() {
        const canvas = this.canvasTarget
        const link = document.createElement('a')
        link.download = this.filenameValue
        link.href = canvas.toDataURL('image/png')
        link.click()
    }
}
