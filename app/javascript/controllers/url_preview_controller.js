import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "preview"]

  connect() {
    this.updatePreview()
  }

  change() {
    this.updatePreview()
  }

  updatePreview() {
    const url = this.inputTarget.value.trim()
    if (!url) {
      this.previewTarget.innerHTML = ""
      this.previewTarget.classList.add("hidden")
      return
    }

    const youtubeId = this.extractYoutubeId(url)
    if (youtubeId) {
      this.previewTarget.innerHTML = `
        <div class="mt-2 rounded-lg overflow-hidden border border-gray-200">
          <iframe width="100%" height="200" src="https://www.youtube.com/embed/${youtubeId}"
            frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
            allowfullscreen class="rounded-lg"></iframe>
        </div>`
      this.previewTarget.classList.remove("hidden")
      return
    }

    const spotifyUri = this.extractSpotifyUri(url)
    if (spotifyUri) {
      this.previewTarget.innerHTML = `
        <div class="mt-2 rounded-lg overflow-hidden border border-gray-200">
          <iframe src="https://open.spotify.com/embed/${spotifyUri}" width="100%" height="152"
            frameborder="0" allow="autoplay; clipboard-write; encrypted-media; fullscreen; picture-in-picture"
            loading="lazy" class="rounded-lg"></iframe>
        </div>`
      this.previewTarget.classList.remove("hidden")
      return
    }

    // Generic URL — show as link
    this.previewTarget.innerHTML = `
      <p class="mt-2 text-xs text-gray-500">
        <a href="${this.escapeHtml(url)}" target="_blank" rel="noopener noreferrer" class="text-pink-600 hover:text-pink-700 underline break-all">
          ${this.escapeHtml(url)}
        </a>
      </p>`
    this.previewTarget.classList.remove("hidden")
  }

  extractYoutubeId(url) {
    const patterns = [
      /(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/)([a-zA-Z0-9_-]{11})/,
      /youtube\.com\/shorts\/([a-zA-Z0-9_-]{11})/
    ]
    for (const pattern of patterns) {
      const match = url.match(pattern)
      if (match) return match[1]
    }
    return null
  }

  extractSpotifyUri(url) {
    const match = url.match(/open\.spotify\.com\/(track|album|playlist|artist|episode|show)\/([a-zA-Z0-9]+)/)
    if (match) return `${match[1]}/${match[2]}`
    return null
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
