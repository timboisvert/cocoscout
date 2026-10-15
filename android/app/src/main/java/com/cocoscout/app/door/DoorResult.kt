package com.cocoscout.app.door

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * What a scan came to, as the door page shows it in its banner
 * (door_controller.js showBanner), sent over to show on the camera. Like
 * DoorResult.swift.
 */
@Serializable
data class DoorResult(
    val tone: Tone = Tone.ERROR,
    /** The first line is the big one: the name, or what went wrong. */
    val lines: List<String?> = emptyList(),
    /** Set on a fresh admit, which the door can take back for a couple of minutes. */
    @SerialName("undo_ticket_id") val undoTicketId: String? = null,
    val items: List<Item> = emptyList(),
    /** The same result redrawn (an item just delivered): no sound or buzz. */
    val quiet: Boolean = false
) {
    @Serializable
    enum class Tone {
        @SerialName("admitted") ADMITTED,
        @SerialName("already") ALREADY,
        @SerialName("error") ERROR
    }

    /** Something they pre-bought (a bottle) to hand over, with its Delivered address. */
    @Serializable
    data class Item(
        val id: Int,
        val label: String,
        val fulfilled: Boolean = false,
        @SerialName("fulfill_url") val fulfillUrl: String
    )

    val shownLines: List<String> get() = lines.filterNotNull()

    /** Something still to hand over keeps the result up until the next scan. */
    val waitingOnDelivery: Boolean get() = items.any { !it.fulfilled }
}
