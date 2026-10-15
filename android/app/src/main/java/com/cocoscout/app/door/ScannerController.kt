package com.cocoscout.app.door

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.View
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** What the scanner screen shows; ScannerScreen draws it. Like ScannerModel in the iOS app. */
class ScannerModel(val title: String, val subtitle: String) {
    enum class Camera { STARTING, RUNNING, UNAVAILABLE, DENIED }

    var camera by mutableStateOf(Camera.STARTING)
    var hasTorch by mutableStateOf(false)
    var torchOn by mutableStateOf(false)
    var result by mutableStateOf<DoorResult?>(null)
    /** A code went to the page and its answer isn't back yet. */
    var waiting by mutableStateOf(false)
    /** Delivered taps on their way. */
    val delivering = mutableStateListOf<String>()
    var typedCode by mutableStateOf("")
}

/**
 * One open scanner: takes codes from the camera (or typed), sends each to the
 * door page once, and shows the page's answer with a sound and a buzz. Like
 * ScannerViewController.swift, minus the camera (ScannerScreen has that).
 */
class ScannerController(title: String, subtitle: String, private val onEvent: (Event) -> Unit) {
    sealed class Event {
        data class Code(val code: String) : Event()
        data class Undo(val ticketId: String) : Event()
        data class Fulfill(val url: String) : Event()
        data object Closed : Event()
    }

    val model = ScannerModel(title, subtitle)
    private val feedback = DoorFeedback()
    private val handler = Handler(Looper.getMainLooper())
    private var lastCode: Pair<String, Long>? = null
    private val stopWaiting = Runnable { model.waiting = false }
    private val hideResult = Runnable { model.result = null }
    /** The scanner's view, for the buzz. */
    var view: View? = null

    fun found(raw: String, typed: Boolean = false) {
        val code = raw.trim()
        if (code.isEmpty() || model.waiting) return
        val now = SystemClock.elapsedRealtime()
        // The camera sees the same code many times a second.
        lastCode?.let { (last, at) -> if (!typed && last == code && now - at < REPEAT_WINDOW_MS) return }
        lastCode = code to now

        model.waiting = true
        if (typed) model.typedCode = ""
        onEvent(Event.Code(code))
        // Never stuck: if the page doesn't answer, scanning picks up again.
        handler.removeCallbacks(stopWaiting)
        handler.postDelayed(stopWaiting, 8_000)
    }

    fun show(result: DoorResult) {
        handler.removeCallbacks(stopWaiting)
        model.waiting = false
        model.delivering.clear()
        model.result = result
        if (!result.quiet) view?.let { feedback.play(result.tone, it) }
        // Gone after a few seconds, unless something is still to hand over.
        handler.removeCallbacks(hideResult)
        if (!result.waitingOnDelivery) handler.postDelayed(hideResult, RESULT_MS)
    }

    fun undo(ticketId: String) = onEvent(Event.Undo(ticketId))

    fun fulfill(url: String) {
        model.delivering.add(url)
        onEvent(Event.Fulfill(url))
    }

    fun closed() {
        handler.removeCallbacksAndMessages(null)
        feedback.release()
        onEvent(Event.Closed)
    }

    companion object {
        private const val REPEAT_WINDOW_MS = 4_000L
        private const val RESULT_MS = 8_000L

        /** The open scanner, for its screen to find (one at a time). */
        var current: ScannerController? = null
    }
}
