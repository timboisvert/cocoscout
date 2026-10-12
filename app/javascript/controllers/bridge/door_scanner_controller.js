import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Bridge Component: the app's own camera at the door (Door/ScannerViewController
// in the iOS app). It sits beside the door controller. When the door asks to
// scan, the app opens a full-screen scanner instead of the page's camera; each
// code comes back here and goes through the door's own check-in, and each
// result goes back to show over the camera. The app also keeps the phone
// awake while the door page is open. In a browser nothing here runs, and the
// page's camera scans as before.
export default class extends BridgeComponent {
  static component = "door-scanner"
  static values = { title: String, subtitle: String }

  connect() {
    super.connect()
    this.send("connect")
  }

  disconnect() {
    super.disconnect()
    this.send("disconnect")
  }

  // door:scan. The app takes it when it can; the door then leaves its own
  // camera off.
  open(event) {
    if (!this.enabled) return

    event.preventDefault()
    this.send("open", { title: this.titleValue, subtitle: this.subtitleValue }, (message) => {
      const { action, value } = message.data
      // door-scanner:code, :undo, :fulfill or :closed, for the door controller.
      this.dispatch(action, { detail: { value }, prefix: "door-scanner" })
    })
  }

  // door:result. Shown over the camera while it's open; the app ignores it
  // otherwise.
  result({ detail }) {
    if (this.enabled) this.send("result", detail)
  }
}
