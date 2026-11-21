package com.cocoscout.app.bridge

import android.graphics.Color
import android.text.SpannableString
import android.text.style.ForegroundColorSpan
import android.view.Menu
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import android.widget.AbsoluteLayout
import androidx.appcompat.widget.PopupMenu
import androidx.core.view.MenuCompat
import dev.hotwire.core.bridge.BridgeComponent
import dev.hotwire.core.bridge.BridgeDelegate
import dev.hotwire.core.bridge.Message
import dev.hotwire.navigation.destinations.HotwireDestination
import kotlinx.serialization.Serializable

/**
 * A page's Section row opens the phone's own menu (Tim, 2026-11-20), in
 * place of the page's slide-up sheet. The page (bridge/sections_controller.js)
 * takes the tap and sends where the row is and what the sections are; the
 * menu drops from that spot, and the pick goes back to the page, which opens
 * that section exactly as the sheet's row would. Like SectionsComponent.swift.
 */
@Suppress("DEPRECATION") // AbsoluteLayout is what a WebView is: its children sit at page positions and scroll with it.
class SectionsComponent(
    name: String,
    private val delegate: BridgeDelegate<HotwireDestination>
) : BridgeComponent<HotwireDestination>(name, delegate) {

    override fun onReceive(message: Message) {
        when (message.event) {
            "open" -> message.data<MessageData>()?.let { open(it) }
        }
    }

    private fun open(data: MessageData) {
        val webView = delegate.destination.fragment.view?.let { findWebView(it) } ?: return
        val density = webView.resources.displayMetrics.density
        val rect = data.rect

        // Something for the menu to drop from: a clear view over the row.
        val anchor = View(webView.context)
        webView.addView(
            anchor,
            AbsoluteLayout.LayoutParams(
                (rect.width * density).toInt(), (rect.height * density).toInt(),
                (rect.x * density).toInt(), (rect.y * density).toInt()
            )
        )

        val popup = PopupMenu(webView.context, anchor)
        data.groups.forEachIndexed { number, group ->
            if (group.title.isNotEmpty()) popup.menu.add(number, Menu.NONE, Menu.NONE, group.title).isEnabled = false
            group.items.forEach { item ->
                val title: CharSequence = if (item.danger) {
                    SpannableString(item.title).apply { setSpan(ForegroundColorSpan(Color.rgb(0xDC, 0x26, 0x26)), 0, length, 0) }
                } else {
                    item.title
                }
                // Item ids start at 1: 0 is Menu.NONE.
                popup.menu.add(number, item.index + 1, Menu.NONE, title).apply {
                    if (item.selected) {
                        isCheckable = true
                        isChecked = true
                    }
                }
            }
        }
        MenuCompat.setGroupDividerEnabled(popup.menu, true)
        popup.setOnMenuItemClickListener { picked ->
            replyTo("open", Pick(picked.itemId - 1))
            true
        }
        popup.setOnDismissListener { webView.removeView(anchor) }
        anchor.post { popup.show() }
    }

    private fun findWebView(view: View): WebView? {
        if (view is WebView) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) findWebView(view.getChildAt(i))?.let { return it }
        }
        return null
    }

    @Serializable
    data class MessageData(val rect: Rect, val groups: List<Group>)

    @Serializable
    data class Rect(val x: Float, val y: Float, val width: Float, val height: Float)

    @Serializable
    data class Group(val title: String, val items: List<Item>)

    @Serializable
    data class Item(val index: Int, val title: String, val selected: Boolean, val danger: Boolean, val locked: Boolean)

    @Serializable
    data class Pick(val index: Int)
}
