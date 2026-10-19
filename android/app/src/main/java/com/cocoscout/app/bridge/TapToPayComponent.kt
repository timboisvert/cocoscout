package com.cocoscout.app.bridge

import androidx.lifecycle.lifecycleScope
import com.cocoscout.app.MainActivity
import com.cocoscout.app.door.TapToPayLocation
import com.cocoscout.app.door.TapToPayPayment
import com.cocoscout.app.door.TapToPayReader
import com.cocoscout.app.door.TapToPayScreens
import com.cocoscout.app.door.TapToPaySetup
import dev.hotwire.core.bridge.BridgeComponent
import dev.hotwire.core.bridge.BridgeDelegate
import dev.hotwire.core.bridge.Message
import dev.hotwire.navigation.destinations.HotwireDestination
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable

/**
 * Tap to Pay (bridge/tap_to_pay_controller.js), on Stripe Terminal's Tap to
 * Pay reader. The same messages as TapToPayComponent.swift, so the door
 * pages drive both apps alike:
 *
 * - "pay": the door page holds seats for a sale. Get the reader ready
 *   (showing "Getting Tap to Pay ready" if that takes a moment), the guide
 *   the first time, then the buyer's tap on Stripe's own screen, and reply
 *   { status: "paid" | "failed" | "canceled", message, paymentIntentId, declined }.
 * - "status" / "enable": Tap to Pay's own page asks how this phone stands,
 *   and sets it up. The answers keep coming while it gets ready.
 * - "howToTap": the guide again, from either page.
 */
class TapToPayComponent(
    name: String,
    private val delegate: BridgeDelegate<HotwireDestination>
) : BridgeComponent<HotwireDestination>(name, delegate) {

    private val fragment get() = delegate.destination.fragment
    private var listening: Job? = null

    override fun onReceive(message: Message) {
        val activity = fragment.activity as? MainActivity ?: return
        when (message.event) {
            "howToTap" -> fragment.lifecycleScope.launch { TapToPayScreens.howToTap(activity) }
            "status" -> {
                val data = message.data<ReaderData>() ?: return
                answer("status", TapToPaySetup.currentState(data.locationId, data.connectionTokenUrl))
                listen()
            }
            "enable" -> {
                val data = message.data<ReaderData>() ?: return
                listen()
                fragment.lifecycleScope.launch {
                    val state = TapToPaySetup.enable(activity, data.locationId, data.connectionTokenUrl)
                    answer("enable", state)
                    if (state == TapToPaySetup.State.Ready && !TapToPayScreens.hasShownHowToTap(activity)) {
                        TapToPayScreens.howToTap(activity)
                    }
                }
            }
            "pay" -> {
                val sale = message.data<TapToPayPayment>() ?: return
                fragment.lifecycleScope.launch { pay(activity, sale) }
            }
        }
    }

    private suspend fun pay(activity: MainActivity, sale: TapToPayPayment) {
        // Location first, so the "getting ready" screen never sits under Android's question.
        if (!TapToPayLocation.ask(activity)) return reply(Answer("failed", TapToPayReader.locationMessage))
        val state = TapToPayScreens.preparingAround {
            TapToPaySetup.ensureReady(activity, sale.locationId, sale.connectionTokenUrl)
        }
        when (state) {
            TapToPaySetup.State.Ready -> Unit
            is TapToPaySetup.State.Failed -> return reply(Answer("failed", state.message))
            else -> return reply(Answer("failed", "Tap to Pay isn't ready yet. Try again in a moment."))
        }

        if (!TapToPayScreens.hasShownHowToTap(activity)) TapToPayScreens.howToTap(activity)

        val outcome = TapToPayReader.take(activity, sale)
        reply(Answer(outcome.status, outcome.message, outcome.paymentIntentId, outcome.declined))
    }

    /** Tap to Pay's page hears every change while it's showing. */
    private fun listen() {
        if (listening?.isActive == true) return
        val owner = fragment.viewLifecycleOwnerLiveData.value ?: fragment
        listening = owner.lifecycleScope.launch {
            TapToPaySetup.state.drop(1).collect { answer("status", it) }
        }
    }

    private fun answer(event: String, state: TapToPaySetup.State) {
        replyTo(event, StateAnswer.of(state))
    }

    private fun reply(answer: Answer) {
        replyTo("pay", answer)
    }

    /** What Tap to Pay's page sends with "status" and "enable". */
    @Serializable
    data class ReaderData(val connectionTokenUrl: String, val locationId: String = "")

    @Serializable
    data class Answer(
        val status: String,
        val message: String? = null,
        val paymentIntentId: String? = null,
        val declined: Boolean = false
    )

    @Serializable
    data class StateAnswer(val state: String, val progress: Float? = null, val message: String? = null) {
        companion object {
            fun of(state: TapToPaySetup.State) = when (state) {
                TapToPaySetup.State.NotSetUp -> StateAnswer("notSetUp")
                is TapToPaySetup.State.Preparing -> StateAnswer("preparing", progress = state.progress)
                TapToPaySetup.State.Ready -> StateAnswer("ready")
                is TapToPaySetup.State.Failed -> StateAnswer("failed", message = state.message)
            }
        }
    }
}
