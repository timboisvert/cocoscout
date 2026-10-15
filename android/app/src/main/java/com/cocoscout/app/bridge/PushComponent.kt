package com.cocoscout.app.bridge

import androidx.lifecycle.lifecycleScope
import com.cocoscout.app.MainActivity
import com.cocoscout.app.push.PushRegistrar
import dev.hotwire.core.bridge.BridgeComponent
import dev.hotwire.core.bridge.BridgeDelegate
import dev.hotwire.core.bridge.Message
import dev.hotwire.navigation.destinations.HotwireDestination
import kotlinx.coroutines.launch

/**
 * Push notifications on this phone, for the web side
 * (bridge/push_controller.js). Like PushComponent.swift:
 *
 * - "sync": where they stand and the token, on every page, so the server
 *   keeps this phone filed under whoever's signed in.
 * - "request": Android's "Allow notifications?", then the same answer.
 * - "open-settings": CocoScout's notification settings, the only place they
 *   can be turned off.
 */
class PushComponent(
    name: String,
    private val delegate: BridgeDelegate<HotwireDestination>
) : BridgeComponent<HotwireDestination>(name, delegate) {

    private val fragment get() = delegate.destination.fragment

    override fun onReceive(message: Message) {
        val activity = fragment.activity as? MainActivity ?: return
        when (message.event) {
            "sync" -> fragment.lifecycleScope.launch {
                replyTo("sync", PushRegistrar.state(activity))
            }
            "request" -> fragment.lifecycleScope.launch {
                replyTo("request", PushRegistrar.request(activity))
            }
            "open-settings" -> PushRegistrar.openSettings(activity)
        }
    }
}
