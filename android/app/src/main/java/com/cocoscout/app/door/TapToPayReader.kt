package com.cocoscout.app.door

import android.content.Context
import android.content.pm.PackageManager
import android.webkit.CookieManager
import com.cocoscout.app.BuildConfig
import com.stripe.stripeterminal.Terminal
import com.stripe.stripeterminal.external.callable.Callback
import com.stripe.stripeterminal.external.callable.ConnectionTokenCallback
import com.stripe.stripeterminal.external.callable.ConnectionTokenProvider
import com.stripe.stripeterminal.external.callable.DiscoveryListener
import com.stripe.stripeterminal.external.callable.InternetReaderListener
import com.stripe.stripeterminal.external.callable.PaymentIntentCallback
import com.stripe.stripeterminal.external.callable.ReaderCallback
import com.stripe.stripeterminal.external.callable.TapToPayReaderListener
import com.stripe.stripeterminal.external.callable.TerminalListener
import com.stripe.stripeterminal.external.models.CaptureMethod
import com.stripe.stripeterminal.external.models.ConnectionConfiguration
import com.stripe.stripeterminal.external.models.ConnectionConfiguration.InternetConnectionConfiguration
import com.stripe.stripeterminal.external.models.ConnectionConfiguration.TapToPayConnectionConfiguration
import com.stripe.stripeterminal.external.models.ConnectionStatus
import com.stripe.stripeterminal.external.models.ConnectionTokenException
import com.stripe.stripeterminal.external.models.DeviceType
import com.stripe.stripeterminal.external.models.DiscoveryConfiguration
import com.stripe.stripeterminal.external.models.DiscoveryConfiguration.InternetDiscoveryConfiguration
import com.stripe.stripeterminal.external.models.DiscoveryConfiguration.TapToPayDiscoveryConfiguration
import com.stripe.stripeterminal.external.models.LocaleConfig
import com.stripe.stripeterminal.external.models.PaymentIntent
import com.stripe.stripeterminal.external.models.PaymentIntentParameters
import com.stripe.stripeterminal.external.models.PaymentIntentStatus
import com.stripe.stripeterminal.external.models.Reader
import com.stripe.stripeterminal.external.models.SimulatedCard
import com.stripe.stripeterminal.external.models.SimulatedCardType
import com.stripe.stripeterminal.external.models.SimulatorConfiguration
import com.stripe.stripeterminal.external.models.TapUseCase
import com.stripe.stripeterminal.external.models.TerminalErrorCode
import com.stripe.stripeterminal.external.models.TerminalException
import com.stripe.stripeterminal.log.LogLevel
import dev.hotwire.core.config.Hotwire
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.net.HttpURLConnection
import java.net.URL
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * The phone as a card reader: Stripe Terminal's Tap to Pay on Android. Like
 * TapToPayReader.swift.
 *
 * One reader for the app. The first tap connects the phone to Terminal as a
 * reader at the organization's Location (the server picks the Location when
 * it makes the connection token); later taps reuse the connection. The
 * PaymentIntent is made here, by the SDK, from what the server sends
 * (TapToPay.payment_params). Every step reports a plain status + message
 * back to the door page, which shows it and offers another go.
 *
 * Debug builds (against the Mac's server with test keys) use Stripe's
 * simulated Tap to Pay reader; release builds the phone's own NFC, which
 * Stripe allows only in a build that isn't debuggable, on a phone with
 * Developer options off. Tap to Pay won't run on the emulator at all, not
 * even simulated (it has no NFC), so there a debug build's sale goes
 * through Stripe's simulated countertop reader instead (standsIn).
 */
object TapToPayReader {
    data class Outcome(
        val status: String, // paid, failed, canceled
        val message: String? = null,
        val paymentIntentId: String? = null,
        /** The card itself was declined (not a connection or setup problem), so the buyer gets a receipt saying so. */
        val declined: Boolean = false
    )

    private val simulated = BuildConfig.DEBUG

    @Volatile private var connectionTokenUrl: String? = null
    private var appContext: Context? = null

    /**
     * The Location this phone last connected at. Kept here rather than read
     * back from the SDK's reader, which doesn't always report it (the
     * simulated reader doesn't), so a connected phone is never connected again.
     */
    private var connectedLocationId: String? = null

    /** The sale's PaymentIntent while it's being paid, so a declined card tries again on the same one. */
    private var pending: Pair<String, PaymentIntent>? = null

    /**
     * A debug build on the emulator: Stripe's simulated countertop reader
     * stands in for Tap to Pay at the same Location, and a dialog plays the
     * buyer (TapToPayScreens.emulatorTap). The token, the PaymentIntent,
     * settling and the receipt all go the real way. Never in a release build.
     */
    private fun standsIn(context: Context) =
        BuildConfig.DEBUG && !context.packageManager.hasSystemFeature(PackageManager.FEATURE_NFC)

    /** Takes the sale's payment (TapToPaySetup.ensureReady comes first, so it's normally connected already). */
    suspend fun take(context: Context, sale: TapToPayPayment): Outcome {
        val orderId = sale.stripeMetadata["ticket_order_id"].orEmpty()
        return try {
            connect(context, sale.locationId, sale.connectionTokenUrl)
            val intent = paymentIntent(sale, orderId)
            val tap = if (standsIn(context)) TapToPayScreens.emulatorTap() else null
            when (tap) {
                TapToPayScreens.EmulatorTap.Decline -> Terminal.getInstance().simulatorConfiguration =
                    SimulatorConfiguration(simulatedCard = SimulatedCard(SimulatedCardType.CHARGE_DECLINED))
                else -> if (tap != null) Terminal.getInstance().simulatorConfiguration = SimulatorConfiguration()
            }
            val collected = collectPaymentMethod(intent, cancelAtOnce = tap == TapToPayScreens.EmulatorTap.Cancel)
            val confirmed = confirmPaymentIntent(collected)
            if (confirmed.status != PaymentIntentStatus.SUCCEEDED && confirmed.status != PaymentIntentStatus.REQUIRES_CAPTURE) {
                pending = orderId to confirmed
                return Outcome("failed", "The payment wasn't approved.", declined = true)
            }
            pending = null
            Outcome("paid", paymentIntentId = confirmed.id)
        } catch (e: TerminalException) {
            when (e.errorCode) {
                TerminalErrorCode.CANCELED, TerminalErrorCode.CANCELED_BY_READER -> Outcome("canceled")
                TerminalErrorCode.DECLINED_BY_STRIPE_API, TerminalErrorCode.DECLINED_BY_READER -> {
                    // Declined: the same PaymentIntent takes the next card.
                    e.paymentIntent?.let { pending = orderId to it }
                    val why = plain(e.errorMessage)?.let { " $it" }.orEmpty()
                    Outcome("failed", "The payment wasn't approved.$why", declined = true)
                }
                else -> Outcome("failed", message(e))
            }
        } catch (e: Exception) {
            Outcome("failed", message(e))
        }
    }

    // Connecting

    /** Connected as a reader at this Location (a door at another organization connects afresh). */
    fun isConnected(locationId: String): Boolean =
        Terminal.isInitialized() &&
            Terminal.getInstance().connectionStatus == ConnectionStatus.CONNECTED &&
            connectedLocationId == locationId

    /** The phone as a Tap to Pay reader at the organization's Location. */
    suspend fun connect(context: Context, locationId: String, tokenUrl: String) {
        connectionTokenUrl = tokenUrl
        if (isConnected(locationId)) return
        if (locationId.isBlank()) throw TapToPayError(noLocationMessage)
        if (!TapToPayLocation.isGranted(context)) throw TapToPayError(locationMessage)

        start(context)
        val terminal = Terminal.getInstance()
        if (terminal.connectionStatus == ConnectionStatus.CONNECTED) disconnect()
        connectedLocationId = null

        val reader: Reader
        val connection: ConnectionConfiguration
        if (standsIn(context)) {
            reader = discoverReader(InternetDiscoveryConfiguration(location = locationId, isSimulated = true))
            connection = InternetConnectionConfiguration(internetReaderListener = object : InternetReaderListener {}, failIfInUse = false)
        } else {
            val discovery = TapToPayDiscoveryConfiguration(isSimulated = simulated)
            val support = terminal.supportsReadersOfType(DeviceType.TAP_TO_PAY_DEVICE, discovery)
            if (!support.isSupported) throw support.error ?: TapToPayError(unsupportedMessage)
            reader = discoverReader(discovery)
            connection = TapToPayConnectionConfiguration(
                useCase = TapUseCase.Pay(locationId),
                autoReconnectOnUnexpectedDisconnect = true,
                tapToPayReaderListener = object : TapToPayReaderListener {}
            )
        }
        suspendCancellableCoroutine { continuation ->
            terminal.connectReader(reader, connection, object : ReaderCallback {
                override fun onSuccess(reader: Reader) = continuation.resume(Unit)
                override fun onFailure(e: TerminalException) = continuation.resumeWithException(e)
            })
        }
        connectedLocationId = locationId
    }

    /** Stripe Terminal, once per launch, with the token from whichever door is selling. */
    private fun start(context: Context) {
        appContext = context.applicationContext
        if (Terminal.isInitialized()) return
        Terminal.init(
            context.applicationContext,
            if (BuildConfig.DEBUG) LogLevel.VERBOSE else LogLevel.NONE,
            TokenProvider,
            object : TerminalListener {},
            null,
            LocaleConfig.HardcodedLocale.Builder("en-US").build()
        )
    }

    private suspend fun disconnect() = suspendCancellableCoroutine { continuation ->
        Terminal.getInstance().disconnectReader(object : Callback {
            override fun onSuccess() = continuation.resume(Unit)
            override fun onFailure(e: TerminalException) = continuation.resume(Unit)
        })
    }

    /** The phone itself, as Terminal finds it. Discovery ends when it's connected. */
    private suspend fun discoverReader(configuration: DiscoveryConfiguration): Reader =
        suspendCancellableCoroutine { continuation ->
            var done = false
            val discovery = Terminal.getInstance().discoverReaders(
                configuration,
                object : DiscoveryListener {
                    override fun onUpdateDiscoveredReaders(readers: List<Reader>) {
                        val reader = readers.firstOrNull() ?: return
                        if (done) return
                        done = true
                        continuation.resume(reader)
                    }
                },
                object : Callback {
                    override fun onSuccess() {}
                    override fun onFailure(e: TerminalException) {
                        if (done) return
                        done = true
                        continuation.resumeWithException(e)
                    }
                }
            )
            continuation.invokeOnCancellation { if (!discovery.isCompleted) discovery.cancel(ignored) }
        }

    // The sale

    /** This sale's PaymentIntent: the one already started for it, or a new one carrying the order's total and metadata. */
    private suspend fun paymentIntent(sale: TapToPayPayment, orderId: String): PaymentIntent {
        pending?.let { (pendingOrder, intent) ->
            if (pendingOrder == orderId && intent.status == PaymentIntentStatus.REQUIRES_PAYMENT_METHOD) return intent
        }
        val params = PaymentIntentParameters.Builder()
            .setAmount(sale.amountCents)
            .setCurrency(sale.currency)
            .setCaptureMethod(CaptureMethod.Automatic)
            .setMetadata(sale.stripeMetadata)
            .setDescription(sale.description)
            .setTransferGroup(sale.transferGroup)
            .build()
        val intent = suspendCancellableCoroutine { continuation ->
            Terminal.getInstance().createPaymentIntent(params, intentCallback(continuation))
        }
        pending = orderId to intent
        return intent
    }

    /**
     * Stripe's own full-screen Tap to Pay screen takes the buyer's card, then
     * hands back here. cancelAtOnce: the emulator's buyer backed out.
     */
    private suspend fun collectPaymentMethod(intent: PaymentIntent, cancelAtOnce: Boolean = false): PaymentIntent =
        suspendCancellableCoroutine { continuation ->
            val collecting = Terminal.getInstance().collectPaymentMethod(intent, intentCallback(continuation))
            if (cancelAtOnce) collecting.cancel(ignored)
            continuation.invokeOnCancellation { if (!collecting.isCompleted) collecting.cancel(ignored) }
        }

    private suspend fun confirmPaymentIntent(intent: PaymentIntent): PaymentIntent =
        suspendCancellableCoroutine { continuation ->
            Terminal.getInstance().confirmPaymentIntent(intent, intentCallback(continuation))
        }

    private fun intentCallback(continuation: kotlinx.coroutines.CancellableContinuation<PaymentIntent>) =
        object : PaymentIntentCallback {
            override fun onSuccess(paymentIntent: PaymentIntent) = continuation.resume(paymentIntent)
            override fun onFailure(e: TerminalException) = continuation.resumeWithException(e)
        }

    private val ignored = object : Callback {
        override fun onSuccess() {}
        override fun onFailure(e: TerminalException) {}
    }

    // In plain words

    const val noTokenMessage = "Couldn't reach our payment provider. Check the connection and try again."
    const val locationMessage = "Tap to Pay needs location access, as card networks require. Allow it in Settings > Apps > CocoScout > Permissions > Location."
    private const val noLocationMessage = "Tap to Pay needs the venue's address first. Ask your organization's manager to add it in Manage > Settings > Locations."
    private const val unsupportedMessage = "This phone can't take Tap to Pay. It needs NFC and Android 13 or later, with Google Play."

    /**
     * What an error means for the person holding the phone, in words that
     * never name the payment provider.
     */
    fun message(error: Throwable): String {
        if (error is TapToPayError) return error.message
        if (error !is TerminalException) return plain(error.message) ?: noTokenMessage
        return when (error.errorCode) {
            TerminalErrorCode.TAP_TO_PAY_UNSUPPORTED_DEVICE,
            TerminalErrorCode.TAP_TO_PAY_UNSUPPORTED_PROCESSOR,
            TerminalErrorCode.TAP_TO_PAY_LIBRARY_NOT_INCLUDED -> unsupportedMessage
            TerminalErrorCode.TAP_TO_PAY_UNSUPPORTED_ANDROID_VERSION,
            TerminalErrorCode.ANDROID_API_LEVEL_ERROR ->
                "Tap to Pay needs a newer version of Android, or a newer security update. Update this phone in Settings > System > Software update."
            TerminalErrorCode.TAP_TO_PAY_DEVICE_TAMPERED ->
                "Tap to Pay can't run on this phone, because its software has been changed (rooted or unlocked)."
            TerminalErrorCode.TAP_TO_PAY_DEBUG_NOT_SUPPORTED ->
                "Tap to Pay can't take payments while Developer options are on. Turn them off in Settings > System > Developer options."
            TerminalErrorCode.TAP_TO_PAY_INSECURE_ENVIRONMENT ->
                "Tap to Pay stopped because something else could see the screen. Stop any screen recording or sharing, turn off Developer options, and close apps that draw over others, then try again."
            TerminalErrorCode.TAP_TO_PAY_PIN_UNAVAILABLE ->
                "This card needs a PIN, which this phone can't take right now. Ask for another card or another way to pay."
            TerminalErrorCode.TAP_TO_PAY_NFC_DISABLED ->
                "Turn on NFC in this phone's Settings (search Settings for NFC), then try again."
            TerminalErrorCode.LOCATION_SERVICES_DISABLED ->
                "Tap to Pay needs Location turned on, as card networks require. Turn it on in Settings > Location, then try again."
            TerminalErrorCode.CARD_READ_TIMED_OUT -> "The card wasn't read in time. Try again."
            TerminalErrorCode.STRIPE_API_CONNECTION_ERROR,
            TerminalErrorCode.REQUEST_TIMED_OUT,
            TerminalErrorCode.SESSION_EXPIRED -> noTokenMessage
            // The server's own words when it couldn't make a token (no venue address, say).
            TerminalErrorCode.CONNECTION_TOKEN_PROVIDER_ERROR ->
                (error.cause as? ConnectionTokenException)?.message ?: plain(error.cause?.message) ?: noTokenMessage
            else -> plain(error.errorMessage) ?: "Tap to Pay hit a problem. Try again."
        }
    }

    /** A message from the SDK, unless it names the payment provider (door staff never hear its name). */
    private fun plain(text: String?): String? =
        text?.trim()?.takeIf { it.isNotEmpty() && !it.contains("stripe", ignoreCase = true) }

    // The connection token

    /**
     * The server mints the token (door#tap_connection_token, or
     * door#tap_to_pay_token from the setup page) with the web view's cookies,
     * so Terminal knows which organization is selling.
     */
    private object TokenProvider : ConnectionTokenProvider {
        private val json = Json { ignoreUnknownKeys = true }

        override fun fetchConnectionToken(callback: ConnectionTokenCallback) {
            val url = connectionTokenUrl ?: return callback.onFailure(ConnectionTokenException(noTokenMessage))
            Thread {
                try {
                    val connection = URL(url).openConnection() as HttpURLConnection
                    CookieManager.getInstance().getCookie(url)?.let { connection.setRequestProperty("Cookie", it) }
                    connection.setRequestProperty("Accept", "application/json")
                    appContext?.let { connection.setRequestProperty("User-Agent", Hotwire.config.userAgentWithWebViewDefault(it)) }
                    val ok = connection.responseCode in 200..299
                    val body = (if (ok) connection.inputStream else connection.errorStream)?.bufferedReader()?.use { it.readText() }.orEmpty()
                    connection.disconnect()
                    val fields = runCatching { json.parseToJsonElement(body).jsonObject }.getOrNull()
                    val secret = fields?.get("secret")?.jsonPrimitive?.content
                    if (ok && !secret.isNullOrBlank()) {
                        callback.onSuccess(secret)
                    } else {
                        val error = fields?.get("error")?.jsonPrimitive?.content
                        callback.onFailure(ConnectionTokenException(plain(error) ?: noTokenMessage))
                    }
                } catch (e: Exception) {
                    callback.onFailure(ConnectionTokenException(noTokenMessage, e))
                }
            }.start()
        }
    }
}

/** What bridge/tap_to_pay_controller.js sends with "pay". */
@Serializable
data class TapToPayPayment(
    val amountCents: Long,
    val currency: String,
    val description: String,
    /** The PaymentIntent's metadata (the bridge keeps "metadata" for itself). */
    val stripeMetadata: Map<String, String> = emptyMap(),
    val transferGroup: String,
    val connectionTokenUrl: String,
    val locationId: String = "",
    val label: String = "",
    /** The door the sale is at. */
    val doorPath: String? = null
)

/** A reason Tap to Pay can't go ahead, already in plain words. */
class TapToPayError(override val message: String) : Exception(message)
