import { Controller } from "@hotwired/stimulus"

// Drives the distance-origin modal's geolocation path. When the user
// clicks "Use my location", we ask the browser, then submit a hidden
// form to /mics/origin with the resulting lat/lng. The address path is
// a plain HTML form — no JS needed there.
export default class extends Controller {
  static targets = ["useMeButton", "geoStatus", "geoForm", "latInput", "lngInput"]

  useGeolocation() {
    if (!navigator.geolocation) {
      this.setStatus("error", "Your browser doesn't support geolocation.")
      return
    }
    this.setStatus("loading", "Requesting your location…")
    this.useMeButtonTarget.disabled = true

    navigator.geolocation.getCurrentPosition(
      (pos) => {
        this.latInputTarget.value = pos.coords.latitude
        this.lngInputTarget.value = pos.coords.longitude
        this.geoFormTarget.submit()
      },
      (err) => {
        this.useMeButtonTarget.disabled = false
        let msg
        switch (err.code) {
          case err.PERMISSION_DENIED:
            msg = "Location blocked — you can still type an address below."
            break
          case err.POSITION_UNAVAILABLE:
            msg = "Your browser couldn't get a fix on your location."
            break
          case err.TIMEOUT:
            msg = "Took too long. Try again, or use an address below."
            break
          default:
            msg = "Couldn't get your location."
        }
        this.setStatus("error", msg)
      },
      { enableHighAccuracy: false, timeout: 8000, maximumAge: 60000 }
    )
  }

  setStatus(kind, text) {
    const el = this.geoStatusTarget
    el.textContent = text
    el.className = "mt-2 text-xs " + (
      kind === "error"   ? "text-red-600" :
      kind === "loading" ? "text-gray-500 italic" :
      "text-gray-500"
    )
  }
}
