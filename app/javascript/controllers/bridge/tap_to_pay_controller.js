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
  static values = { payment: Object, connectionTokenUrl: String, locationId: String, label: String, canAcceptTerms: Boolean, doorPath: String }

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
      label: this.labelValue,
      canAcceptTerms: this.canAcceptTermsValue,
      doorPath: this.doorPathValue
    }
    this.send("pay", data, (message) => {
      // { status: "paid" | "failed" | "canceled", message, paymentIntentId, declined }
      this.dispatch("done", { detail: message.data, prefix: "tap-to-pay" })
    })
  }

  // "How to take a tap": Apple's guide again (the app shows it before the first tap too).
  howToTap() {
    if (this.enabled) this.send("howToTap")
  }

  // Tap to Pay on iPhone's page (door/tap_to_pay): how this iPhone stands,
  // and setting it up (Apple's terms, then the guide). The app answers, and
  // keeps answering while it gets ready, with { state: "notSetUp" |
  // "preparing" | "ready" | "needsAdmin" | "failed", progress, message },
  // dispatched as tap-to-pay:state.
  status() {
    if (!this.enabled) return
    this.send("status", this.readerData(), (message) => this.dispatch("state", { detail: message.data, prefix: "tap-to-pay" }))
  }

  enable(event) {
    if (!this.enabled) return

    event?.preventDefault()
    this.send("enable", this.readerData(), (message) => this.dispatch("state", { detail: message.data, prefix: "tap-to-pay" }))
  }

  readerData() {
    return {
      connectionTokenUrl: new URL(this.connectionTokenUrlValue, window.location.href).toString(),
      locationId: this.locationIdValue,
      canAcceptTerms: this.canAcceptTermsValue
    }
  }
}
