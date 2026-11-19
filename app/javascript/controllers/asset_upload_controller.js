import { Controller } from "@hotwired/stimulus"

// One image on a visual asset request (Tim, 2026-11-19): pick or drop a
// file, check it here first (type, size, and for a picture its shape and
// pixels), then send it with a progress bar. The server checks it again
// (AssetCheck) and answers with the card redrawn and the progress line, or
// with the sentence saying why it can't be used. The production's own
// Visual Assets tab reloads instead (reload value).
export default class extends Controller {
  static targets = ["input", "zone", "idle", "progress", "bar", "percent", "filename", "error"]
  static values = {
    url: String, spec: Number, width: Number, height: Number, types: Array, formats: String,
    maxBytes: Number, maxMb: Number, ratio: String, shape: String, reload: Boolean
  }

  pick(event) {
    event?.preventDefault()
    this.inputTarget.click()
  }

  choose() {
    const file = this.inputTarget.files[0]
    if (file) this.handle(file)
  }

  dragOver(event) {
    event.preventDefault()
    this.element.classList.add("ring-2", "ring-pink-400")
  }

  dragLeave() {
    this.element.classList.remove("ring-2", "ring-pink-400")
  }

  drop(event) {
    event.preventDefault()
    this.dragLeave()
    const file = event.dataTransfer?.files?.[0]
    if (file) this.handle(file)
  }

  async handle(file) {
    this.clearError()
    const problem = await this.problemWith(file)
    if (problem) {
      this.showError(problem)
      this.inputTarget.value = ""
      return
    }
    this.send(file)
  }

  // The same sentences the server would give, so a wrong file is answered
  // before it is sent. The server still decides.
  async problemWith(file) {
    const label = `"${file.name.length > 60 ? file.name.slice(0, 57) + "..." : file.name}"`
    if (file.type && this.typesValue.length && !this.typesValue.includes(file.type)) {
      return `We couldn't use ${label}. This one needs to be ${this.formatsValue}.`
    }
    if (this.maxBytesValue && file.size > this.maxBytesValue) {
      const mb = Math.round((file.size / 1048576) * 10) / 10
      return `We couldn't use ${label}. It is ${mb} MB, and this one can be up to ${this.maxMbValue} MB.`
    }
    if (!/^image\/(jpeg|png|webp)$/.test(file.type)) return null

    const size = await this.pixels(file)
    if (!size) return null
    const [w, h] = size
    const want = this.widthValue / this.heightValue
    const have = w / h
    if (Math.abs(have - want) / want > 0.01) {
      const theirs = Math.abs(have - 1) <= 0.01 ? "square" : (have > 1 ? "wider than it is tall" : "taller than it is wide")
      const ours = this.shapeValue === "square" ? "square" : `${this.shapeValue} (${this.ratioValue})`
      return `We couldn't use ${label}. It is ${w} × ${h}, which is ${theirs}. This one needs to be ${ours}, ${this.widthValue} × ${this.heightValue} or larger.`
    }
    if (w < this.widthValue || h < this.heightValue) {
      return `We couldn't use ${label}. It is ${w} × ${h}, which is the right shape but too small. This one needs to be at least ${this.widthValue} × ${this.heightValue}.`
    }
    return null
  }

  async pixels(file) {
    try {
      const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" })
      const size = [bitmap.width, bitmap.height]
      bitmap.close?.()
      return size
    } catch (_error) {
      return null
    }
  }

  send(file) {
    const form = new FormData()
    form.append("file", file)
    form.append("spec_id", this.specValue)
    const name = document.getElementById("asset-uploader-name")?.value
    if (name) form.append("uploader_name", name)

    this.showProgress(file.name)
    const xhr = new XMLHttpRequest()
    xhr.open("POST", this.urlValue)
    xhr.setRequestHeader("Accept", "application/json")
    xhr.setRequestHeader("X-CSRF-Token", document.querySelector("meta[name='csrf-token']")?.content || "")
    xhr.upload.addEventListener("progress", (event) => {
      if (!event.lengthComputable) return
      const pct = Math.round((event.loaded / event.total) * 100)
      this.barTarget.style.width = `${pct}%`
      this.percentTarget.textContent = pct < 100 ? `Uploading, ${pct}%` : "Checking the file"
    })
    xhr.addEventListener("load", () => this.answered(xhr))
    xhr.addEventListener("error", () => this.failed("The upload didn't finish. Check your connection and try again."))
    xhr.send(form)
  }

  answered(xhr) {
    let data = null
    try { data = JSON.parse(xhr.responseText) } catch (_error) { data = null }
    if (!data) return this.failed("Something went wrong on our side. Try again in a moment.")
    if (!data.ok) return this.failed(data.message)

    if (this.reloadValue || !data.card_html) {
      window.Turbo ? window.Turbo.visit(window.location.href, { action: "replace" }) : window.location.reload()
      return
    }
    const progress = document.getElementById("asset-progress")
    if (progress && data.progress_html) progress.outerHTML = data.progress_html
    this.element.outerHTML = data.card_html
  }

  failed(message) {
    this.hideProgress()
    this.inputTarget.value = ""
    this.showError(message)
  }

  showProgress(name) {
    this.filenameTarget.textContent = name
    this.barTarget.style.width = "0%"
    this.percentTarget.textContent = "Uploading"
    this.idleTarget.classList.add("hidden")
    this.progressTarget.classList.remove("hidden")
  }

  hideProgress() {
    this.progressTarget.classList.add("hidden")
    this.idleTarget.classList.remove("hidden")
  }

  showError(message) {
    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("hidden")
  }

  clearError() {
    this.errorTarget.textContent = ""
    this.errorTarget.classList.add("hidden")
  }
}
