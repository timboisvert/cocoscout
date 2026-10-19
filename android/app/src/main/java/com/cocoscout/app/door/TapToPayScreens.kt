package com.cocoscout.app.door

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.cocoscout.app.ui.ButtonSize
import com.cocoscout.app.ui.ButtonVariant
import com.cocoscout.app.ui.SharedButton
import com.cocoscout.app.ui.Tailwind
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow

/**
 * Tap to Pay's own screens over the page: how to take a tap, and "Getting
 * Tap to Pay ready" over a sale whose reader isn't connected yet. Drawn by
 * TapToPayOverlay, beside the menu button (MainActivity). Like HowToTap.swift
 * and TapToPayPreparing.swift.
 */
object TapToPayScreens {
    sealed interface Screen {
        data object HowToTap : Screen
        data object Preparing : Screen
        data object EmulatorTap : Screen
    }

    /** What the emulator's buyer does (TapToPayReader.standsIn). */
    enum class EmulatorTap { Approve, Decline, Cancel }

    val showing = MutableStateFlow<Screen?>(null)
    private var howToTapClosed: CompletableDeferred<Unit>? = null
    private var emulatorTapped: CompletableDeferred<EmulatorTap>? = null

    private const val HOW_TO_TAP_SHOWN = "howToTapShown"

    private fun prefs(context: Context) = context.getSharedPreferences("tap_to_pay", Context.MODE_PRIVATE)

    fun hasShownHowToTap(context: Context) = prefs(context).getBoolean(HOW_TO_TAP_SHOWN, false)

    /** The guide, returning once it's been closed. Shown before someone's first tap, and whenever they ask. */
    suspend fun howToTap(context: Context) {
        prefs(context).edit().putBoolean(HOW_TO_TAP_SHOWN, true).apply()
        val closed = CompletableDeferred<Unit>().also { howToTapClosed = it }
        showing.value = Screen.HowToTap
        closed.await()
    }

    fun closeHowToTap() {
        if (showing.value == Screen.HowToTap) showing.value = null
        howToTapClosed?.complete(Unit)
        howToTapClosed = null
    }

    /** Debug builds on the emulator only: the buyer's card, played by whoever's testing. */
    suspend fun emulatorTap(): EmulatorTap {
        val tapped = CompletableDeferred<EmulatorTap>().also { emulatorTapped = it }
        showing.value = Screen.EmulatorTap
        return tapped.await()
    }

    fun emulatorTapped(tap: EmulatorTap) {
        if (showing.value == Screen.EmulatorTap) showing.value = null
        emulatorTapped?.complete(tap)
        emulatorTapped = null
    }

    /** Runs work, showing "Getting Tap to Pay ready" if it takes over 300 ms, and gone the moment it's done. */
    suspend fun <T> preparingAround(work: suspend () -> T): T = coroutineScope {
        val showingSoon = async {
            delay(300)
            showing.value = Screen.Preparing
        }
        try {
            work()
        } finally {
            showingSoon.cancel()
            if (showing.value == Screen.Preparing) showing.value = null
        }
    }
}

/** Whichever Tap to Pay screen is up, as a dialog over everything. */
@Composable
fun TapToPayOverlay() {
    val screen by TapToPayScreens.showing.collectAsState()
    when (screen) {
        TapToPayScreens.Screen.HowToTap -> Dialog(onDismissRequest = TapToPayScreens::closeHowToTap) {
            Card {
                Title("How to take a tap")
                Body(
                    "When this phone asks for payment, have the buyer hold their contactless card, or their phone or " +
                        "watch, flat against the spot the screen points to (on most phones, the back near the camera), " +
                        "and keep it there until it checks. If their card asks for a PIN, they enter it on this screen."
                )
                SharedButton("Got it", onClick = TapToPayScreens::closeHowToTap, size = ButtonSize.Large, fullWidth = true)
            }
        }
        TapToPayScreens.Screen.Preparing -> Dialog(
            onDismissRequest = {},
            properties = DialogProperties(dismissOnBackPress = false, dismissOnClickOutside = false)
        ) {
            Card(Modifier.semantics { liveRegion = LiveRegionMode.Polite }) {
                Title("Getting Tap to Pay ready")
                LinearProgressIndicator(
                    modifier = Modifier.fillMaxWidth(),
                    color = Tailwind.Pink500,
                    trackColor = Tailwind.Gray300
                )
                Body("Tap to Pay will be ready in a moment.")
            }
        }
        TapToPayScreens.Screen.EmulatorTap -> Dialog(
            onDismissRequest = { TapToPayScreens.emulatorTapped(TapToPayScreens.EmulatorTap.Cancel) }
        ) {
            Card {
                Title("Simulated tap")
                Body("The emulator has no NFC, so a simulated card reader stands in for Tap to Pay. What does the buyer's card do?")
                SharedButton("Approve", onClick = { TapToPayScreens.emulatorTapped(TapToPayScreens.EmulatorTap.Approve) }, fullWidth = true)
                SharedButton("Decline", onClick = { TapToPayScreens.emulatorTapped(TapToPayScreens.EmulatorTap.Decline) },
                    variant = ButtonVariant.Secondary, fullWidth = true)
                SharedButton("Cancel", onClick = { TapToPayScreens.emulatorTapped(TapToPayScreens.EmulatorTap.Cancel) },
                    variant = ButtonVariant.Secondary, fullWidth = true)
            }
        }
        null -> Unit
    }
}

@Composable
private fun Card(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Column(
        modifier = modifier
            .widthIn(max = 340.dp)
            .background(androidx.compose.ui.graphics.Color.White, RoundedCornerShape(16.dp))
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) { content() }
}

@Composable
private fun Title(text: String) {
    Text(text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Tailwind.Gray900)
}

@Composable
private fun Body(text: String) {
    Text(text, fontSize = 14.sp, lineHeight = 20.sp, color = Tailwind.Gray700)
}
