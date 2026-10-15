package com.cocoscout.app.bridge

import android.view.Menu
import android.view.MenuItem
import dev.hotwire.core.bridge.BridgeComponent
import dev.hotwire.core.bridge.BridgeDelegate
import dev.hotwire.core.bridge.Message
import dev.hotwire.navigation.destinations.HotwireDestination
import kotlinx.serialization.Serializable

/**
 * A page's main form button in the toolbar (bridge/form_controller.js sends
 * its title; tapping it asks the page to submit). Only pages that ask, with
 * data-bridge-title.
 */
class FormComponent(
    name: String,
    private val delegate: BridgeDelegate<HotwireDestination>
) : BridgeComponent<HotwireDestination>(name, delegate) {

    private val itemId = 37

    override fun onReceive(message: Message) {
        when (message.event) {
            "connect" -> message.data<MessageData>()?.let { addButton(it.title) }
            "disconnect" -> removeButton()
        }
    }

    private fun addButton(title: String) {
        val menu = delegate.destination.toolbarForNavigation()?.menu ?: return
        menu.removeItem(itemId)
        menu.add(Menu.NONE, itemId, 999, title).apply {
            setShowAsAction(MenuItem.SHOW_AS_ACTION_ALWAYS)
            setOnMenuItemClickListener { replyTo("connect") }
        }
    }

    private fun removeButton() {
        delegate.destination.toolbarForNavigation()?.menu?.removeItem(itemId)
    }

    @Serializable
    data class MessageData(val title: String)
}
