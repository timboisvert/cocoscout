import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "canvas"]
    static values = { url: String, logoUrl: String }

    connect() {
        // Load QRCode library dynamically if not already loaded
        this.loadQRCodeLibrary()
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
        const size = 280

        if (typeof qrcode === 'undefined') {
            console.error('QRCode library not loaded')
            return
        }

        try {
            // Generate QR code using qrcode-generator
            // Type 0 = auto-detect, Error correction H = high (30%)
            const qr = qrcode(0, 'H')
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

            // Draw QR code modules in pink
            ctx.fillStyle = '#ec4899'
            for (let row = 0; row < moduleCount; row++) {
                for (let col = 0; col < moduleCount; col++) {
                    if (qr.isDark(row, col)) {
                        ctx.fillRect(col * cellSize, row * cellSize, cellSize, cellSize)
                    }
                }
            }

            // Draw logo in center
            this.drawLogo(canvas)
        } catch (error) {
            console.error('QR Code generation failed:', error)
        }
    }

    drawLogo(canvas) {
        const ctx = canvas.getContext('2d')
        const logo = new Image()
        logo.crossOrigin = 'anonymous'
        logo.src = this.logoUrlValue

        logo.onload = () => {
            // Calculate center position for logo
            const logoSize = canvas.width * 0.22  // Logo is 22% of QR code size
            const logoX = (canvas.width - logoSize) / 2
            const logoY = (canvas.height - logoSize) / 2

            // Draw white circle background for logo
            ctx.beginPath()
            ctx.arc(canvas.width / 2, canvas.height / 2, logoSize / 2 + 4, 0, Math.PI * 2)
            ctx.fillStyle = '#ffffff'
            ctx.fill()

            // Draw logo
            ctx.drawImage(logo, logoX, logoY, logoSize, logoSize)
        }
    }

    download() {
        const canvas = this.canvasTarget
        const link = document.createElement('a')
        link.download = 'cocoscout-qr-code.png'
        link.href = canvas.toDataURL('image/png')
        link.click()
    }
}
