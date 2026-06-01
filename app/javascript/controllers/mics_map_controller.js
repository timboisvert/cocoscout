import { Controller } from "@hotwired/stimulus"
import * as L from "leaflet"

// Renders a Leaflet map of mics on a city/hub page.
//
// Data attributes (set in the view):
//   data-mics-map-mics-value     JSON array of { slug, name, lat, lng, venue, url, day, time }
//   data-mics-map-center-value   "lat,lng"  (optional; defaults to the centroid of mics)
//   data-mics-map-zoom-value     integer    (optional; defaults to 11)
export default class extends Controller {
  static values = {
    mics:   Array,
    center: String,
    zoom:   Number
  }

  connect() {
    // Inject Leaflet CSS once per page if it isn't already there.
    if (!document.querySelector("link[data-leaflet-css]")) {
      const link = document.createElement("link")
      link.rel = "stylesheet"
      link.href = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"
      link.setAttribute("data-leaflet-css", "true")
      document.head.appendChild(link)
    }

    const mics = (this.hasMicsValue ? this.micsValue : []).filter(m => m.lat && m.lng)
    const center = this.parseCenter(mics)
    const zoom = this.hasZoomValue ? this.zoomValue : 11

    this.map = L.map(this.element, { scrollWheelZoom: true }).setView(center, zoom)

    // CartoDB Positron — light, minimal, easy on the eyes. Free for
    // open use; attribution links to OSM + Carto per their terms.
    L.tileLayer("https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png", {
      maxZoom: 19,
      subdomains: "abcd",
      attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors ' +
        '&copy; <a href="https://carto.com/attributions">CARTO</a>'
    }).addTo(this.map)

    const pinkIcon = L.divIcon({
      className: "mic-pin",
      html: '<div class="w-3 h-3 rounded-full bg-pink-500 border-2 border-white shadow-md"></div>',
      iconSize: [14, 14],
      iconAnchor: [7, 7]
    })

    const bounds = []
    mics.forEach(m => {
      const marker = L.marker([m.lat, m.lng], { icon: pinkIcon }).addTo(this.map)
      marker.bindPopup(this.popupHtml(m))
      bounds.push([m.lat, m.lng])
    })

    if (bounds.length > 1) {
      this.map.fitBounds(bounds, { padding: [30, 30] })
    }
  }

  disconnect() {
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  }

  parseCenter(mics) {
    if (this.hasCenterValue && this.centerValue.includes(",")) {
      const [lat, lng] = this.centerValue.split(",").map(parseFloat)
      return [lat, lng]
    }
    if (mics.length === 0) return [41.8781, -87.6298] // Chicago fallback
    const lat = mics.reduce((s, m) => s + m.lat, 0) / mics.length
    const lng = mics.reduce((s, m) => s + m.lng, 0) / mics.length
    return [lat, lng]
  }

  popupHtml(m) {
    const safe = s => String(s ?? "").replace(/[<>&"]/g, c => ({"<":"&lt;",">":"&gt;","&":"&amp;","\"":"&quot;"})[c])
    return `
      <div style="min-width:180px">
        <div style="font-weight:700;font-size:14px"><a href="${safe(m.url)}" style="color:#db2777;text-decoration:none">${safe(m.name)}</a></div>
        <div style="font-size:12px;color:#555;margin-top:2px">${safe(m.venue)}</div>
        <div style="font-size:11px;color:#888;margin-top:4px">${safe(m.day)} · ${safe(m.time)}</div>
      </div>
    `
  }
}
