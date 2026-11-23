package com.cocoscout.app.signin

import android.content.Context
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.ui.layout.layout
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import com.cocoscout.app.MainActivity
import com.cocoscout.app.R
import com.cocoscout.app.ui.Tailwind
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * "Sign in with your fingerprint next time" (Android 5 on
 * https://claude.ai/artifact/X1sA6FoXBSPJseGxFzdExn): after someone signs in
 * here with a code or a password, a sheet rises over their first page
 * offering a passkey, so next time their fingerprint or screen lock signs
 * them in. Turn it on opens Credential Manager's own sheet; Not now isn't
 * asked again for that account on this phone, and the Account page's Add a
 * passkey is always there. Mirrors PasskeyOffer.swift.
 */
object PasskeyOffer {
    private const val PREFS = "passkeys"
    private const val DECLINED = "declined"
    private const val MADE = "made"

    /** The account the sheet is offering a passkey for, while it's up. */
    var showing by mutableStateOf<KnownAccount?>(null)

    sealed interface Outcome {
        data class Added(val name: String) : Outcome
        data object Canceled : Outcome
        data object Exists : Outcome
        data class Failed(val message: String) : Outcome
    }

    /** After a code or password sign-in, unless this account already said Not now, or made one, on this phone. */
    fun shouldOffer(context: Context, account: KnownAccount?): Boolean {
        if (account == null || account.method !in setOf("code", "password")) return false
        val email = account.email.lowercase()
        return email !in list(context, DECLINED) && email !in list(context, MADE)
    }

    fun remember(context: Context, email: String, made: Boolean) {
        val key = if (made) MADE else DECLINED
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putStringSet(key, list(context, key) + email.lowercase()).apply()
    }

    private fun list(context: Context, key: String): Set<String> =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getStringSet(key, emptySet()) ?: emptySet()

    /**
     * The whole of making one: App::PasskeysController's options, Credential
     * Manager's sheet, and the new passkey back to the server. Also the
     * Account page's Add a passkey (bridge/PasskeyComponent).
     */
    suspend fun make(activity: MainActivity): Outcome {
        val options = SignInClient.text(activity, "/app/passkeys/options")
        if (options == null || "\"challenge\"" !in options) {
            val message = options?.let { runCatching { Json.parseToJsonElement(it) as? JsonObject }.getOrNull()?.get("message")?.jsonPrimitive?.content }
            return Outcome.Failed(message ?: "Passkeys can't be added right now. Please try again.")
        }
        return when (val made = Credentials.createPasskey(activity, options)) {
            is Credentials.Made.Passkey -> {
                val body = buildJsonObject { put("credential", Json.parseToJsonElement(made.json)) }.toString()
                val answer = SignInClient.text(activity, "/app/passkeys", body)
                    ?.let { runCatching { Json.parseToJsonElement(it) as? JsonObject }.getOrNull() }
                if (answer?.get("status")?.jsonPrimitive?.content == "added") {
                    Outcome.Added(answer["name"]?.jsonPrimitive?.content ?: "Google Password Manager")
                } else {
                    Outcome.Failed(answer?.get("message")?.jsonPrimitive?.content ?: "That passkey couldn't be added. Please try again.")
                }
            }
            Credentials.Made.Canceled -> Outcome.Canceled
            Credentials.Made.Exists -> Outcome.Exists
            Credentials.Made.Failed -> Outcome.Failed("That passkey couldn't be added. Please try again.")
        }
    }
}

private val Coustard = FontFamily(Font(R.font.coustard_regular))
private val Gray500 = Color(0xFF6A7282)
private val Pink50 = Color(0xFFFDF2F8)
private val Pink200 = Color(0xFFFCCEE8)
private val Pink700 = Color(0xFFC4005F)
private const val COCO_RATIO = 768f / 721f

private fun Modifier.overlapBelow(overlap: Dp) = layout { measurable, constraints ->
    val placeable = measurable.measure(constraints)
    val height = (placeable.height - overlap.roundToPx()).coerceAtLeast(0)
    layout(placeable.width, height) { placeable.place(0, 0) }
}

@Composable
fun PasskeyOfferOverlay() {
    val account = PasskeyOffer.showing ?: return
    val activity = LocalContext.current as MainActivity
    val scope = rememberCoroutineScope()
    var shown by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(account) { shown = true }

    fun close() {
        shown = false
        scope.launch {
            delay(300)
            PasskeyOffer.showing = null
        }
    }

    fun notNow() {
        if (busy) return
        PasskeyOffer.remember(activity, account.email, made = false)
        close()
    }

    Dialog(
        onDismissRequest = { notNow() },
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)
    ) {
        // The dialog's own dimming would stack on this one's, hiding the page.
        val window = (LocalView.current.parent as? DialogWindowProvider)?.window
        SideEffect { window?.setDimAmount(0f) }
        Box(Modifier.fillMaxSize()) {
            AnimatedVisibility(shown, enter = fadeIn(), exit = fadeOut()) {
                Box(
                    Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.4f))
                        .clickable(remember { MutableInteractionSource() }, indication = null) { notNow() }
                )
            }
            AnimatedVisibility(
                shown, modifier = Modifier.align(Alignment.BottomCenter),
                enter = slideInVertically { it }, exit = slideOutVertically { it }
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    // The peek: 220 wide, 150 showing over the sheet.
                    Image(painterResource(R.drawable.coco), contentDescription = null, contentScale = ContentScale.FillWidth,
                        modifier = Modifier.width(220.dp).overlapBelow(220.dp * COCO_RATIO - 150.dp))
                    Column(
                        Modifier.fillMaxWidth()
                            .background(Color.White, RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp))
                            .navigationBarsPadding()
                            .padding(start = 24.dp, end = 24.dp, top = 26.dp, bottom = 12.dp)
                    ) {
                        Text("Sign in with your fingerprint next time", modifier = Modifier.semantics { heading() },
                            style = TextStyle(fontFamily = Coustard, fontSize = 26.sp, lineHeight = 31.sp, color = Tailwind.Gray900))
                        Spacer(Modifier.height(8.dp))
                        Text(
                            (if (account.method == "code") "No code to wait for." else "No password to type.") +
                                " Your fingerprint or screen lock signs you in on this phone.",
                            fontSize = 16.sp, lineHeight = 23.sp, color = Gray500
                        )
                        error?.let {
                            Spacer(Modifier.height(16.dp))
                            Text(it, fontSize = 15.sp, color = Pink700,
                                modifier = Modifier.fillMaxWidth().background(Pink50, RoundedCornerShape(12.dp))
                                    .border(1.dp, Pink200, RoundedCornerShape(12.dp)).padding(12.dp))
                        }
                        Spacer(Modifier.height(36.dp))
                        Button(
                            onClick = {
                                if (busy) return@Button
                                busy = true
                                error = null
                                scope.launch {
                                    val outcome = PasskeyOffer.make(activity)
                                    busy = false
                                    when (outcome) {
                                        is PasskeyOffer.Outcome.Added, PasskeyOffer.Outcome.Exists -> {
                                            PasskeyOffer.remember(activity, account.email, made = true)
                                            SignInFlow.rememberMethod(activity, account, "passkey")
                                            close()
                                        }
                                        PasskeyOffer.Outcome.Canceled -> Unit
                                        is PasskeyOffer.Outcome.Failed -> error = outcome.message
                                    }
                                }
                            },
                            modifier = Modifier.fillMaxWidth().height(56.dp),
                            shape = RoundedCornerShape(28.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = Tailwind.Pink500, contentColor = Color.White)
                        ) {
                            if (busy) {
                                CircularProgressIndicator(Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
                            } else {
                                Icon(Icons.Filled.Fingerprint, contentDescription = null, modifier = Modifier.size(20.dp))
                            }
                            Spacer(Modifier.size(10.dp))
                            Text("Turn it on", fontSize = 17.sp, fontWeight = FontWeight.Medium)
                        }
                        Box(Modifier.fillMaxWidth().padding(top = 6.dp), contentAlignment = Alignment.Center) {
                            TextButton(onClick = { notNow() }, enabled = !busy, modifier = Modifier.height(48.dp)) {
                                Text("Not now", color = Tailwind.Pink600, fontWeight = FontWeight.Medium, fontSize = 16.sp)
                            }
                        }
                    }
                }
            }
        }
    }
}
