package com.cocoscout.app.bridge

import androidx.lifecycle.lifecycleScope
import com.cocoscout.app.MainActivity
import com.cocoscout.app.signin.PasskeyOffer
import dev.hotwire.core.bridge.BridgeComponent
import dev.hotwire.core.bridge.BridgeDelegate
import dev.hotwire.core.bridge.Message
import dev.hotwire.navigation.destinations.HotwireDestination
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable

/**
 * Add a passkey on the Account page, in the app (bridge/passkey_controller.js):
 * Credential Manager's own sheet makes it and keeps it in the phone's
 * password manager (PasskeyOffer.make, through App::PasskeysController), and
 * the page reloads to list it. Like PasskeyComponent.swift.
 */
class PasskeyComponent(
    name: String,
    private val delegate: BridgeDelegate<HotwireDestination>
) : BridgeComponent<HotwireDestination>(name, delegate) {

    private val fragment get() = delegate.destination.fragment

    override fun onReceive(message: Message) {
        if (message.event != "add") return
        val activity = fragment.activity as? MainActivity ?: return
        fragment.lifecycleScope.launch {
            val answer = when (val outcome = PasskeyOffer.make(activity)) {
                is PasskeyOffer.Outcome.Added -> Answer("added", outcome.name)
                PasskeyOffer.Outcome.Canceled -> Answer("canceled")
                PasskeyOffer.Outcome.Exists -> Answer("exists", "This phone already has a passkey for your account.")
                is PasskeyOffer.Outcome.Failed -> Answer("failed", outcome.message)
            }
            replyTo("add", answer)
        }
    }

    @Serializable
    data class Answer(val status: String, val message: String? = null)
}
