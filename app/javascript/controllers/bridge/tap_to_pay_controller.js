import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Bridge Component: Tap to Pay on the door phone (Bridge/TapToPayComponent in
// the iOS app, on the Stripe Terminal SDK). It sits beside the door-tap
// controller on door/tap. When the page asks (door-tap:pay), the app connects
// to Terminal with a token from connectionTokenUrl, makes the PaymentIntent
// from payment (TapToPay.payment_params: amount, metadata and so on), takes
// the buyer's tap, confirms it, and answers; the answer comes back as
// tap-to-pay:done, with the PaymentIntent's id, for the page to settle. In a
// browser nothing here runs — the button that leads here only shows in the app.
export default class extends BridgeComponent {
  static component = "tap-to-pay"
  static values = { payment: Object, connectionTokenUrl: String, locationId: String, label: String }

  pay(event) {
    if (!this.enabled) return

    event.preventDefault()
    const payment = this.paymentValue
    const data = {
      amountCents: payment.amount_cents,
      currency: payment.currency,
      description: payment.description,
      // Not "metadata": the bridge stamps its own (the page's URL) on that key.
      stripeMetadata: payment.metadata,
      transferGroup: payment.transfer_group,
      connectionTokenUrl: new URL(this.connectionTokenUrlValue, window.location.href).toString(),
      locationId: this.locationIdValue,
      label: this.labelValue
    }
    this.send("pay", data, (message) => {
      // { status: "paid" | "failed" | "canceled", message, paymentIntentId }
      this.dispatch("done", { detail: message.data, prefix: "tap-to-pay" })
    })
  }
}
