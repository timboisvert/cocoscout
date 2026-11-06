package com.cocoscout.app.bridge

import com.cocoscout.app.AppShell
import dev.hotwire.core.bridge.BridgeComponent
import dev.hotwire.core.bridge.BridgeDelegate
import dev.hotwire.core.bridge.Message
import dev.hotwire.navigation.destinations.HotwireDestination
import dev.hotwire.navigation.fragments.HotwireWebBottomSheetFragment
import kotlinx.serialization.Serializable
import kotlin.math.roundToInt

/**
 * Where the floating Coco button belongs on this page, as the page itself
 * works it out (bridge/menu_button_controller.js): how far above the bottom
 * it must sit to clear a bar pinned there, and whether it should be away
 * altogether (scrolling down, or a sheet over the page). The button gets out
 * of the way, so no page makes room for it (Tim, 2026-11-06). The app only
 * obeys; the rules live on the server. Like MenuButtonComponent.swift.
 */
class MenuButtonComponent(
    name: String,
    private val delegate: BridgeDelegate<HotwireDestination>
) : BridgeComponent<HotwireDestination>(name, delegate) {

    override fun onReceive(message: Message) {
        if (message.event != "place") return
        // A page in a sheet over the screen hides the button by itself, and
        // must not move it for the page underneath.
        if (delegate.destination is HotwireWebBottomSheetFragment) return
        val data = message.data<Placement>() ?: return
        AppShell.placeMenuButton(data.rise.roundToInt(), data.away)
    }

    /** rise: the page's pixels, which are the phone's dp. */
    @Serializable
    data class Placement(val rise: Double = 0.0, val away: Boolean = false)
}
