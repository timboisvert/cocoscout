package com.cocoscout.app.bridge

import com.cocoscout.app.door.DoorResult
import com.cocoscout.app.door.KeepAwake
import com.cocoscout.app.door.ScannerController
import com.cocoscout.app.door.ScannerDialogFragment
import dev.hotwire.core.bridge.BridgeComponent
import dev.hotwire.core.bridge.BridgeDelegate
import dev.hotwire.core.bridge.Message
import dev.hotwire.navigation.destinations.HotwireDestination
import kotlinx.serialization.Serializable

/**
 * The door page's camera, done natively (bridge/door_scanner_controller.js).
 * Like DoorScannerComponent.swift.
 *
 * - "connect" / "disconnect": the door page is open, so the phone stays awake
 *   while it's on screen.
 * - "open": show the scanner. Every code it reads, and every Undo or
 *   Delivered tap on a result, goes back as a reply to this message for the
 *   page to act on; so does closing it.
 * - "result": what the page made of the last code, to show over the camera.
 */
class DoorScannerComponent(
    name: String,
    private val delegate: BridgeDelegate<HotwireDestination>
) : BridgeComponent<HotwireDestination>(name, delegate) {

    private var onDoorPage = false
    private var scanner: ScannerController? = null
    private val awakeKey = "door-page-${System.identityHashCode(this)}"
    private val activity get() = delegate.destination.fragment.activity

    override fun onReceive(message: Message) {
        when (message.event) {
            "connect" -> {
                onDoorPage = true
                KeepAwake.hold(activity, awakeKey)
            }
            "disconnect" -> {
                onDoorPage = false
                KeepAwake.release(activity, awakeKey)
            }
            "open" -> message.data<OpenData>()?.let { open(it.title, it.subtitle) }
            "result" -> message.data<DoorResult>()?.let { scanner?.show(it) }
        }
    }

    override fun onStart() {
        if (onDoorPage) KeepAwake.hold(activity, awakeKey)
    }

    override fun onStop() {
        KeepAwake.release(activity, awakeKey)
    }

    private fun open(title: String, subtitle: String) {
        if (scanner != null) return
        val fragment = delegate.destination.fragment
        val controller = ScannerController(title, subtitle) { event -> send(event) }
        scanner = controller
        ScannerController.current = controller
        ScannerDialogFragment().show(fragment.childFragmentManager, "door-scanner")
    }

    private fun send(event: ScannerController.Event) {
        val answer = when (event) {
            is ScannerController.Event.Code -> Answer("code", event.code)
            is ScannerController.Event.Undo -> Answer("undo", event.ticketId)
            is ScannerController.Event.Fulfill -> Answer("fulfill", event.url)
            ScannerController.Event.Closed -> {
                scanner = null
                ScannerController.current = null
                Answer("closed", null)
            }
        }
        replyTo("open", answer)
    }

    @Serializable
    data class OpenData(val title: String = "", val subtitle: String = "")

    @Serializable
    data class Answer(val action: String, val value: String?)
}
