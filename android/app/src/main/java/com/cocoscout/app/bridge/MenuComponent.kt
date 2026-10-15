package com.cocoscout.app.bridge

import com.cocoscout.app.AppShell
import dev.hotwire.core.bridge.BridgeComponent
import dev.hotwire.core.bridge.BridgeDelegate
import dev.hotwire.core.bridge.Message
import dev.hotwire.navigation.destinations.HotwireDestination
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * The menu (with badges) and who's signed in, sent by every page
 * (bridge/menu_controller.js, NativeAppHelper#native_menu). An empty menu
 * means signed out.
 */
class MenuComponent(
    name: String,
    delegate: BridgeDelegate<HotwireDestination>
) : BridgeComponent<HotwireDestination>(name, delegate) {

    override fun onReceive(message: Message) {
        if (message.event != "update") return
        val data = message.data<MenuData>() ?: return
        AppShell.update(data.menu, data.person, page = message.metadata?.url)
    }

    @Serializable
    data class MenuData(val menu: List<MenuItem> = emptyList(), val person: MenuPerson? = null)
}

/** One menu tile: icon is an SF Symbol name (the iOS app's); MenuIcons maps it. */
@Serializable
data class MenuItem(
    val id: String,
    val title: String,
    val path: String,
    val icon: String,
    val badge: Int? = null,
    val subtitle: String? = null
)

@Serializable
data class MenuPerson(
    val name: String,
    val email: String,
    val initials: String,
    @SerialName("headshot_path") val headshotPath: String? = null
)
