import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Bridge Component: Tap to Pay on the door phone (Bridge/TapToPayComponent in
// the iOS app, on the Stripe Terminal SDK). It sits beside the door-tap
// controller on door/tap. When the page asks (door-tap:pay), the app connects
// to Terminal with a token from connectionTokenUrl, takes the buyer's tap for
// the PaymentIntent behind clientSecret, confirms it, and answers; the answer
// comes back as tap-to-pay:done for the page to settle. In a browser nothing
// here runs — the button that leads here only shows in the app.
export default class extends BridgeComponent {
  static component = "tap-to-pay"
  static values = { clientSecret: String, connectionTokenUrl: String, locationId: String, amountCents: Number, label: String }

  pay(event) {
    if (!this.enabled) return

    event.preventDefault()
    const data = {
      clientSecret: this.clientSecretValue,
      connectionTokenUrl: new URL(this.connectionTokenUrlValue, window.location.href).toString(),
      locationId: this.locationIdValue,
      amountCents: this.amountCentsValue,
      label: this.labelValue
    }
    this.send("pay", data, (message) => {
      // { status: "paid" | "failed" | "canceled", message }
      this.dispatch("done", { detail: message.data, prefix: "tap-to-pay" })
    })
  }
}
