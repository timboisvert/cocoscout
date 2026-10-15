import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Bridge Component: this phone's push notifications (Bridge/PushComponent.swift,
// and bridge/PushComponent.kt on Android, which also says platform "android").
// On every app page it asks the app where notifications stand and keeps the
// server in step (My::PushTokensController): the phone's token is filed under
// this sign-in while they're on, and forgotten once they're turned off in
// the phone's Settings. The settings row and the Home card (push_settings_controller)
// hear the answer as a window push:status event, and ask for a change with
// push:request or push:open-settings.
export default class extends BridgeComponent {
  static component = "push"
  static values = { url: String, session: String }

  connect() {
    super.connect()
    this.send("sync", {}, (message) => this.update(message.data))
  }

  // push:request: the phone's own "Allow notifications?" question.
  request() {
    this.send("request", {}, (message) => this.update(message.data))
  }

  // push:open-settings: CocoScout's notification settings on the phone.
  openSettings() {
    this.send("open-settings")
  }

  async update({ status, token, environment, platform }) {
    window.cocoscoutPushStatus = status
    window.dispatchEvent(new CustomEvent("push:status", { detail: { status } }))
    if (!token) return

    const on = ["authorized", "provisional", "ephemeral"].includes(status)
    // Once per app launch and sign-in is plenty; it also marks the phone as
    // checked in, which the unread-messages email goes by.
    const key = `cocoscout:push:${this.sessionValue}:${on ? "on" : "off"}:${token}`
    if (this.remembered(key)) return
    if (await this.tell(on ? "POST" : "DELETE", { token, environment, platform })) this.remember(key)
  }

  async tell(method, body) {
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    try {
      const response = await fetch(this.urlValue, {
        method,
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
        credentials: "same-origin",
        body: JSON.stringify(body)
      })
      return response.ok
    } catch {
      return false
    }
  }

  remembered(key) {
    try { return window.sessionStorage.getItem(key) === "1" } catch { return false }
  }

  remember(key) {
    try { window.sessionStorage.setItem(key, "1") } catch { /* fine without */ }
  }
}
